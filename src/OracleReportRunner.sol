// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

/// @notice Drop-in for Lido v3 AccountingOracle that turns three flat ints into a
///         valid `Accounting.handleOracleReport(...)` call: simulates the report
///         once to derive `simulatedShareRate`, asks the WithdrawalQueue to compute
///         finalization batches, then submits the real report. The contract is meant
///         to live AT the AccountingOracle proxy address (installed via
///         `anvil_setCode`) so that `msg.sender` matches the locator-resolved AO
///         when Accounting performs its access check.
///
///         All inputs are clamped to ranges that pass `OracleReportSanityChecker`,
///         so any (timeElapsed, increaseHint, sharesToBurnHint) the fuzzer throws
///         in lands on a non-reverting code path. Share rate still moves between
///         reports because the helper allows positive CL-balance growth up to a
///         conservative annual cap (≤ 5% APR-equivalent).

interface ILido {
    function getBeaconStat() external view returns (uint256 depositedValidators, uint256 clValidators, uint256 clBalance);
}

interface ILidoLocator {
    function accounting() external view returns (address);
    function withdrawalQueue() external view returns (address);
    function withdrawalVault() external view returns (address);
    function elRewardsVault() external view returns (address);
    function lido() external view returns (address);
    function burner() external view returns (address);
}

interface IBurner {
    function getSharesRequestedToBurn() external view returns (uint256 cover, uint256 nonCover);
}

struct ReportValues {
    uint256 timestamp;
    uint256 timeElapsed;
    uint256 clValidators;
    uint256 clBalance;
    uint256 withdrawalVaultBalance;
    uint256 elRewardsVaultBalance;
    uint256 sharesRequestedToBurn;
    uint256[] withdrawalFinalizationBatches;
    uint256 simulatedShareRate;
}

struct CalculatedValues {
    uint256 etherToFinalizeWQ;
    uint256 sharesToFinalizeWQ;
    uint256 principalClBalance;
    uint256 withdrawalsVaultTransfer;
    uint256 elRewardsVaultTransfer;
    uint256 sharesToBurnForWithdrawals;
    uint256 totalSharesToBurn;
    uint256 sharesToMintAsFees;
    uint256 preTotalShares;
    uint256 preTotalPooledEther;
    uint256 postInternalShares;
    uint256 postInternalEther;
    uint256 postTotalShares;
    uint256 postTotalPooledEther;
    // feeDistribution intentionally elided — we never read it
}

interface IAccounting {
    function simulateOracleReport(ReportValues calldata _report) external view returns (CalculatedValues memory);
    function handleOracleReport(ReportValues calldata _report) external;
}

uint256 constant MAX_BATCHES_LENGTH = 36;

struct BatchesCalculationState {
    uint256 remainingEthBudget;
    bool finished;
    uint256[MAX_BATCHES_LENGTH] batches;
    uint256 batchesLength;
}

interface IWithdrawalQueue {
    function getLastRequestId() external view returns (uint256);
    function getLastFinalizedRequestId() external view returns (uint256);
    function isPaused() external view returns (bool);
    function calculateFinalizationBatches(
        uint256 _maxShareRate,
        uint256 _maxTimestamp,
        uint256 _maxRequestsPerCall,
        BatchesCalculationState memory _state
    ) external view returns (BatchesCalculationState memory);
}

contract OracleReportRunner {
    ILidoLocator constant LOCATOR = ILidoLocator(0xC1d0b3DE6792Bf6b4b37EccdcC24e45978Cfd2Eb);

    /// @dev Conservative annualized growth cap for CL balance (5% APR-equivalent),
    ///      strictly below the typical on-chain `annualBalanceIncreaseBPLimit` of 10%.
    uint256 constant ANNUAL_BP_BUDGET = 500;
    uint256 constant MAX_BP = 10000;
    uint256 constant ONE_YEAR = 365 days;

    /// @notice Single fuzzing entrypoint. The hint provides three knobs; everything
    ///         else needed for a valid report is read from the live forked state.
    function report(
        uint256 timeElapsedHint,
        uint256 clBalanceIncreaseHint,
        uint256 sharesRequestedToBurnHint
    ) external {
        ILido lido = ILido(LOCATOR.lido());
        IAccounting accounting = IAccounting(LOCATOR.accounting());
        IWithdrawalQueue wq = IWithdrawalQueue(LOCATOR.withdrawalQueue());

        // Read state to bound inputs.
        (, uint256 preClValidators, uint256 preClBalance) = lido.getBeaconStat();

        uint256 timeElapsed = _clamp(timeElapsedHint, 1 hours, 7 days);

        // Allow non-decreasing CL balance only — keeps us out of the negative-rebase
        // branch entirely. Cap delta by a conservative annualized rate.
        uint256 maxDelta = (preClBalance * ANNUAL_BP_BUDGET * timeElapsed) / (MAX_BP * ONE_YEAR);
        uint256 delta = clBalanceIncreaseHint > maxDelta ? maxDelta : clBalanceIncreaseHint;
        uint256 clBalance = preClBalance + delta;

        // Reported vault balances must not exceed the actual on-chain balances —
        // mirror them exactly.
        uint256 wvBalance = LOCATOR.withdrawalVault().balance;
        uint256 elBalance = LOCATOR.elRewardsVault().balance;

        // Burner check: reported sharesRequestedToBurn ≤ actual.
        (uint256 cover, uint256 nonCover) = IBurner(LOCATOR.burner()).getSharesRequestedToBurn();
        uint256 actualToBurn = cover + nonCover;
        uint256 sharesRequestedToBurn = sharesRequestedToBurnHint > actualToBurn ? actualToBurn : sharesRequestedToBurnHint;

        // _report.timestamp >= block.timestamp reverts; use the prior second.
        uint256 ts = block.timestamp - 1;

        // STEP 1: simulate without WQ batches → derive postInternal{Shares,Ether}
        ReportValues memory r = ReportValues({
            timestamp: ts,
            timeElapsed: timeElapsed,
            clValidators: preClValidators,
            clBalance: clBalance,
            withdrawalVaultBalance: wvBalance,
            elRewardsVaultBalance: elBalance,
            sharesRequestedToBurn: sharesRequestedToBurn,
            withdrawalFinalizationBatches: new uint256[](0),
            simulatedShareRate: 0
        });
        CalculatedValues memory v = accounting.simulateOracleReport(r);

        // STEP 2: simulatedShareRate = postTotalPooledEther * 1e27 / postTotalShares
        require(v.postTotalShares > 0, "OracleReportRunner: zero shares");
        uint256 rate = (v.postTotalPooledEther * 1e27) / v.postTotalShares;

        // STEP 3: ask WQ to compute finalization batches (only if anything is queued)
        uint256[] memory batches = _calculateBatches(wq, rate, ts, wvBalance + elBalance);

        // STEP 4: actual report
        r.withdrawalFinalizationBatches = batches;
        r.simulatedShareRate = rate;
        accounting.handleOracleReport(r);
    }

    function _calculateBatches(
        IWithdrawalQueue wq,
        uint256 rate,
        uint256 ts,
        uint256 ethBudgetSeed
    ) internal view returns (uint256[] memory batches) {
        if (wq.isPaused() || wq.getLastRequestId() <= wq.getLastFinalizedRequestId() || ethBudgetSeed == 0) {
            return new uint256[](0);
        }

        BatchesCalculationState memory state;
        state.remainingEthBudget = ethBudgetSeed;
        state.finished = false;

        // Loop with a safety cap to avoid runaway iteration if state machine misbehaves.
        for (uint256 i = 0; i < 50 && !state.finished; ++i) {
            state = wq.calculateFinalizationBatches(rate, ts, 1000, state);
        }

        uint256 n = state.batchesLength;
        batches = new uint256[](n);
        for (uint256 i = 0; i < n; ++i) {
            batches[i] = state.batches[i];
        }
    }

    function _clamp(uint256 x, uint256 lo, uint256 hi) private pure returns (uint256) {
        if (hi <= lo) return lo;
        return lo + (x % (hi - lo + 1));
    }

    // ───────── AccountingOracle compatibility shims ─────────
    //
    // OracleReportSanityChecker.checkAccountingOracleReport reads
    //   IBaseOracle(LIDO_LOCATOR.accountingOracle()).getLastProcessingRefSlot()
    // — and our helper occupies that address. The value only matters if the
    // negative-rebase branch fires, which it does not for non-decreasing CL
    // balance. Returning a sane uint keeps the call from reverting.

    function getLastProcessingRefSlot() external view returns (uint256) {
        return block.number;
    }
}

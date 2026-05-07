// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test, console} from "forge-std/Test.sol";

/// @dev SV-08 (`local_deployment/specs/sv_08_withdrawable_bounded.spec`):
/// withdrawableValue(sv) + locked(sv) + obligations(sv)[1] <= totalValue(sv)
interface IVaultHub {
    struct Int104WithCache {
        int104 value;
        int104 valueOnRefSlot;
        uint48 refSlot;
    }

    struct Report {
        uint104 totalValue;
        int104 inOutDelta;
        uint48 timestamp;
    }

    struct VaultRecord {
        Report report;
        uint96 maxLiabilityShares;
        uint96 liabilityShares;
        Int104WithCache[2] inOutDelta;
        uint128 minimalReserve;
        uint128 redemptionShares;
        uint128 cumulativeLidoFees;
        uint128 settledLidoFees;
    }

    function vaultRecord(address vault) external view returns (VaultRecord memory);
    function totalValue(address vault) external view returns (uint256);
    function isVaultConnected(address vault) external view returns (bool);
    function latestReport(address vault) external view returns (Report memory);
    function withdrawableValue(address vault) external view returns (uint256);
    function locked(address vault) external view returns (uint256);
    function obligations(address vault) external view returns (uint256 obligationsShares, uint256 obligationsFees);
}

interface ILidoLocator {
    function accountingOracle() external view returns (address);
}

interface ILazyOracle {
    function updateReportData(
        uint256 vaultsDataTimestamp,
        uint256 vaultsDataRefSlot,
        bytes32 vaultsDataTreeRoot,
        string memory vaultsDataReportCid
    ) external;

    function updateVaultData(
        address vault,
        uint256 totalValue,
        uint256 cumulativeLidoFees,
        uint256 liabilityShares,
        uint256 maxLiabilityShares,
        uint256 slashingReserve,
        bytes32[] calldata proof
    ) external;

    function latestReportData()
        external
        view
        returns (uint256 timestamp, uint256 refSlot, bytes32 treeRoot, string memory reportCid);
}

interface IDashboard {
    function rebalanceVaultWithShares(uint256 shares) external;
    function stakingVault() external view returns (address);
}

interface IAccessControl {
    function grantRole(bytes32 role, address account) external;
}

/// @dev Reproduces Orca trace: Dashboard(0x4dbf...).rebalanceVaultWithShares from 0x852d... with ~7.20576e16 shares,
///      after bringing vault reports in sync with LazyOracle (same Merkle flow as `testing/test/LazyOracleReport.t.sol`),
///      then evaluates SV-08.
contract WithdrawableValueBound is Test {
    address constant LIDO_LOCATOR = 0xC1d0b3DE6792Bf6b4b37EccdcC24e45978Cfd2Eb;
    address constant VAULT_HUB = 0x1d201BE093d847f6446530Efb0E8Fb426d176709;
    address constant LAZY_ORACLE = 0x5DB427080200c235F2Ae8Cd17A7be87921f7AD6c;
    address constant DASHBOARD = 0x4DbF30678DeB96503997a7C79fB6A74f6B809363;
    address constant REBALANCE_SENDER = 0x852deD011285fe67063a08005c71a85690503Cee;
    /// @dev Sole `DEFAULT_ADMIN_ROLE` holder on this Dashboard at fork block 24779995
    address constant DASHBOARD_DEFAULT_ADMIN = 0x4ca5B264B82224c963a939a6a0A99C14C944Dca9;

    bytes32 constant REBALANCE_ROLE = keccak256("vaults.Permissions.Rebalance");

    uint256 constant NUM_VAULTS = 4;

    address[NUM_VAULTS] vaults = [
        0x6d41b27087BBA7Aa9Df685866F834AF91Fad1472,
        0x750b07D95802bb81Be1a09b002410212Ee45c560,
        0x2814C751847730433c13f74de1e234F8D230853E,
        0x62e0D92cf7B8752b5292B9BCbbacE4cFa1633428
    ];

    /// @dev 7.20576e16 shares from the failing trace
    uint256 constant REBALANCE_SHARES = 72_057_600_000_000_000;

    IVaultHub vaultHub = IVaultHub(VAULT_HUB);
    ILazyOracle lazyOracle = ILazyOracle(LAZY_ORACLE);
    IDashboard dashboard = IDashboard(DASHBOARD);
    IAccessControl dashboardAccess = IAccessControl(DASHBOARD);

    address accountingOracle;

    struct VaultLeafData {
        address vault;
        uint256 totalValue;
        uint256 cumulativeLidoFees;
        uint256 liabilityShares;
        uint256 maxLiabilityShares;
        uint256 slashingReserve;
    }

    function setUp() public {
        vm.createSelectFork("mainnet", 24779995);
        accountingOracle = ILidoLocator(LIDO_LOCATOR).accountingOracle();

        vm.startPrank(DASHBOARD_DEFAULT_ADMIN);
        dashboardAccess.grantRole(REBALANCE_ROLE, REBALANCE_SENDER);
        vm.stopPrank();
    }

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? _efficientHash(a, b) : _efficientHash(b, a);
    }

    function _efficientHash(bytes32 a, bytes32 b) internal pure returns (bytes32 value) {
        assembly {
            mstore(0x00, a)
            mstore(0x20, b)
            value := keccak256(0x00, 0x40)
        }
    }

    function _computeLeaf(VaultLeafData memory d) internal pure returns (bytes32) {
        return keccak256(
            bytes.concat(
                keccak256(
                    abi.encode(
                        d.vault,
                        d.totalValue,
                        d.cumulativeLidoFees,
                        d.liabilityShares,
                        d.maxLiabilityShares,
                        d.slashingReserve
                    )
                )
            )
        );
    }

    function _readLeafData() internal view returns (VaultLeafData[NUM_VAULTS] memory leafData) {
        for (uint256 i = 0; i < NUM_VAULTS; i++) {
            IVaultHub.VaultRecord memory rec = vaultHub.vaultRecord(vaults[i]);
            leafData[i] = VaultLeafData({
                vault: vaults[i],
                totalValue: vaultHub.totalValue(vaults[i]),
                cumulativeLidoFees: rec.cumulativeLidoFees,
                liabilityShares: rec.liabilityShares,
                maxLiabilityShares: rec.maxLiabilityShares,
                slashingReserve: 0
            });
        }
    }

    function _buildTree(
        VaultLeafData[NUM_VAULTS] memory leafData
    ) internal pure returns (bytes32 root, bytes32[NUM_VAULTS] memory leaves, bytes32 H01, bytes32 H23) {
        for (uint256 i = 0; i < NUM_VAULTS; i++) {
            leaves[i] = _computeLeaf(leafData[i]);
        }
        H01 = _hashPair(leaves[0], leaves[1]);
        H23 = _hashPair(leaves[2], leaves[3]);
        root = _hashPair(H01, H23);
    }

    function _buildProofs(
        bytes32[NUM_VAULTS] memory leaves,
        bytes32 H01,
        bytes32 H23
    ) internal pure returns (bytes32[][] memory proofs) {
        proofs = new bytes32[][](NUM_VAULTS);

        proofs[0] = new bytes32[](2);
        proofs[0][0] = leaves[1];
        proofs[0][1] = H23;

        proofs[1] = new bytes32[](2);
        proofs[1][0] = leaves[0];
        proofs[1][1] = H23;

        proofs[2] = new bytes32[](2);
        proofs[2][0] = leaves[3];
        proofs[2][1] = H01;

        proofs[3] = new bytes32[](2);
        proofs[3][0] = leaves[2];
        proofs[3][1] = H01;
    }

    function _applyVaultLeaf(VaultLeafData memory d, bytes32[] memory proof, uint256 reportTimestamp) internal {
        if (!vaultHub.isVaultConnected(d.vault)) return;
        require(reportTimestamp > vaultHub.latestReport(d.vault).timestamp, "report not fresh enough");
        lazyOracle.updateVaultData(
            d.vault, d.totalValue, d.cumulativeLidoFees, d.liabilityShares, d.maxLiabilityShares, d.slashingReserve, proof
        );
    }

    /// @dev Mirrors `1570_fuzzing/testing/test/LazyOracleReport.t.sol` so `VaultHub.rebalance` sees a fresh report.
    function _syncLazyOracleReports() internal {
        VaultLeafData[NUM_VAULTS] memory leafData = _readLeafData();
        (bytes32 root, bytes32[NUM_VAULTS] memory leaves, bytes32 H01, bytes32 H23) = _buildTree(leafData);
        bytes32[][] memory proofs = _buildProofs(leaves, H01, H23);

        uint256 ts = block.timestamp;
        uint256 slot = block.number;

        vm.prank(accountingOracle);
        lazyOracle.updateReportData(ts, slot, root, "sv08-repro-cid");

        for (uint256 i = 0; i < NUM_VAULTS; i++) {
            _applyVaultLeaf(leafData[i], proofs[i], ts);
        }
    }

    function test_sv08_withdrawableBounded_afterRebalanceVaultWithShares() public {
        _syncLazyOracleReports();

        vm.startPrank(REBALANCE_SENDER);
        dashboard.rebalanceVaultWithShares(REBALANCE_SHARES);
        vm.stopPrank();

        address sv = dashboard.stakingVault();

        uint256 withdrawable = vaultHub.withdrawableValue(sv);
        uint256 lockedAmt = vaultHub.locked(sv);
        (, uint256 obligationsFees) = vaultHub.obligations(sv);
        uint256 totalVal = vaultHub.totalValue(sv);

        uint256 lhs = withdrawable + lockedAmt + obligationsFees;
        bool specHolds = lhs <= totalVal;
        uint256 excess;
        if (lhs > totalVal) {
            excess = lhs - totalVal;
        } else {
            excess = totalVal - lhs;
        }
        console.log("=== SV-08 after rebalanceVaultWithShares ===");
        console.log("stakingVault:     ", sv);
        console.log("withdrawableValue:", withdrawable);
        console.log("locked:           ", lockedAmt);
        console.log("obligationsFees:  ", obligationsFees);
        console.log("lhs (w+l+f):      ", lhs);
        console.log("totalValue:       ", totalVal);
        if (!specHolds) {
            console.log("excess over TV:   ", lhs - totalVal);
        } else {
            console.log("amount under TV:  ", totalVal - lhs);
        }

        assertFalse(specHolds, "SV-08: expected withdrawable+locked+fees > totalValue after this rebalance");
    }
}

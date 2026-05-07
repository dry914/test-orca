# Results

In what follows, I outline some of the initial findings of OrCa which warrant further exploration from the Lido team.

## Specifications Violated

### Tier liability does not exceed group limit (mv_02_liability_within_group_limit.spec)

OrCa immediately finds a violation to this property, indicating the property is not satisfied in the *current*
state of the blockchain before fuzzing.

After some investigation, we learned that the issue is with tier 0, which is a special sentinel tier. For this tier, the group share limit is 0 but vaults within this tier can have liability shares, so this value is greater than zero.

Once updated to exclude tier 0, the specification finds no violation (mv_06_tier_liability_within_group_limit_no_tier_zero.spec).

For a test that demonstrates this, see `test/VaultBalanceCheck.t.sol`.

### Staking vault total value bounded by vault ETH balance (sv_05_applied_tv_bounded.spec)

OrCa immediately finds a violation to this property, indicating the property is not satisfied in the *current*
state of the blockchain before fuzzing.

After some investigation, we learned the issue is that this property is incomplete, as the total value also includes the beacon balance as well as balances that can decrease due to slashing, penalty, and other consensus layer events.

For a test that demonstrates this, see `test/TierLiabilityWithinGroupLimit.t.sol`.

### VaultHub connection parameters match tier parameters from OperatorGrid (mv_05_connection_matches_tier_params.spec)

OrCa immediately finds a violation to this property, indicating the property is not satisfied in the *current*
state of the blockchain before fuzzing.

After some investigation, the problem appears to be that the function `OperatorGrid::updateVaultFees` updates the fee parameters on the VaultHub but *not* on the OperatorGrid. It appears this occurred at some point for the vault at 0x62e0D92cf7B8752b5292B9BCbbacE4cFa1633428.

It is not clear if this represents an exploitable vulnerability. We strongly suggest looking into whether or not the discrepancy could lead to further violations. Some immediate concerns we thought of were (1) inconsistent fee values between the VaultHub and OperatorGrid leading to discrepancies in price calculation, (2) inconstisent fee values leading to DoS, (3) forced updates to the VaultHub from the OperatorGrid that can revert the fee values unexpectedly.

For a test that demonstrates this, see `test/VaultConnectionParameterMismatch.t.sol`.

### Force validator exit call should not revert with obligations shortfall (sv_04_force_exit_no_revert.spec)

OrCa finds a violation to this by calling `setLiabilitySharesTarget` and then `forceValidatorExit`.

After some investigation, the problem appears to be that `setLiabilitySharesTarget` creates an obligations shortfall, then one week of time passes, and then the call to `forceValidatorExit` fails with `VaultReportStale`. So, another way `forceValidatorExit` can revert is a stale report, even if there is an obligations shortfall.

For a test that demonstrates this, see `test/ForceValidatorExitRevert.t.sol`.

### Withdrawable amount bounded by total value (sv_08_withdrawable_bounded.spec)

OrCa finds a violation to this by calling `Dashboard::rebalanceVaultWithShares`.

After some investigation, it appears the problem is that the correct spec is really to say that the withdrawable value is always <= the *max* difference of the total value and the sum of the locked and obligations values and zero. The violation that is found here is in the case that 0 is greater than the difference of the total value and sum.

Once updated to include the max, the specification finds no violation (sv_12_withdrawable_bounded_max.spec).

For a test that demonstrates the failure of the original spec, see `test/WithdrawableValueBound.t.sol`.

### Liability shares in default tier do not exceed share limit (mv_04_default_tier_liability_bounded.spec)

OrCa finds a violation to this by calling `OperatorGrid::alterTiers`.

After some investigation, it appears that the violation arises from the fact that `alterTiers` allows governance to altier the tier's share limit without checking that the new share limit is actually greater than the current default liability. This may desired, but we do suggest ensuring that no unexpected consequences can arise from allowing this violation to occur on tier updates.

For a test that demonstrates the failure, see `test/DefaultTierLiabilityBounded.t.sol`.

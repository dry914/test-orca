# Property: The sum of all individual vaults' liability shares within a tier should
# equal the tier's tracked liabilityShares (accounting consistency).
#
# The original invariant iterates over all vaults in each tier, sums their
# liabilityShares from VaultHub, and asserts equality with the tier's own
# liabilityShares field. We don't know which vaults should be considered here,
# so we instead check the necessary (but not sufficient) condition that each
# individual vault's liability shares do not exceed the tier's total tracked
# liabilityShares.
#
# Derived from: fuzz_pr_1570/test/0.8.25/invariant-fuzzing/MultiStakingVaultFuzzing.t.sol
#   function invariant3_tier_liability_consistency()
#
# Struct field index substitutions:
#   vaultTierInfo().tierId = [1]
#   Tier.liabilityShares = [2]

vars: VaultHub vh, OperatorGrid og, StakingVault sv
inv: vh.liabilityShares(address(sv)) <= og.tier(og.vaultTierInfo(address(sv))[1])[2]

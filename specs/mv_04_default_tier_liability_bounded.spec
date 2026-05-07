# Property: The total liability shares across all vaults in the default tier (tier 0)
# should not exceed the default tier's share limit.
#
# The original invariant sums liabilityShares of all vaults assigned to the default
# tier (id = 0) and checks the sum <= default tier's shareLimit. Since the
# OperatorGrid tracks the aggregate tier.liabilityShares, we can check it directly
# against the tier's shareLimit.
#
# Derived from: fuzz_pr_1570/test/0.8.25/invariant-fuzzing/MultiStakingVaultFuzzing.t.sol
#   function invariant4_default_tier_liability_consistency()
#
# Struct field index substitutions:
#   Tier.shareLimit = [1]
#   Tier.liabilityShares = [2]

vars: OperatorGrid og
inv: og.tier(0)[2] <= og.tier(0)[1]

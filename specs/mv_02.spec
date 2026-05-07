# Property: The sum of all tier liability shares within a node operator group
# should not exceed the group's share limit.
#
# The original invariant iterates over all tiers in each group and sums their
# liabilityShares, then checks sum <= group.shareLimit. We don't know which tier IDs
# should be considered here, so we instead check the necessary (but not sufficient) condition that each
# individual tier's liability shares do not exceed the group share limit.
#
# Derived from: fuzz_pr_1570/test/0.8.25/invariant-fuzzing/MultiStakingVaultFuzzing.t.sol
#   function invariant2_group_tier_liabilities_below_group_limit()
#
# Struct field index substitutions:
#   Tier.operator = [0]
#   Tier.liabilityShares = [2]
#   Group.shareLimit = [1]

vars: OperatorGrid og, uint8 tierId
inv: og.tier(tierId)[2] <= og.group(og.tier(tierId)[0])[1]

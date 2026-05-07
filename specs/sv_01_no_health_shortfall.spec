# Property: Staking vault should never go below the rebalance threshold.
# After any transaction, healthShortfallShares for the vault should be zero,
# meaning the vault always maintains sufficient collateral relative to its liabilities.
#
# Derived from: fuzz_pr_1570/test/0.8.25/invariant-fuzzing/StakingVaultsFuzzing.t.sol
#   function invariant_01_liabilityShares_not_above_rebalance_threshold()

vars: VaultHub vh, StakingVault sv
inv: vh.healthShortfallShares(address(sv)) = 0

# Property: When a vault is connected, not pending disconnect, and has non-zero
# liability shares, the total value should satisfy the forced rebalance health threshold.
#
# The original invariant computes:
#   minHealthyTotalValue = ceilDiv(liabilityStETH * 10000, 10000 - forcedRebalanceThresholdBP)
#   totalValue >= minHealthyTotalValue
#
# This V spec uses VaultHub.isVaultHealthy() which encapsulates the same health check,
# guarded by conditions matching the original test's modifiers (connected, not pending
# disconnect) and the early-return on zero liability.
#
# Derived from: fuzz_pr_1570/test/0.8.25/invariant-fuzzing/StakingVaultsFuzzing.t.sol
#   function invariant_10_totalValue_should_satisfy_forced_rebalance_threshold()

vars: VaultHub vh, StakingVault sv
inv: (vh.isVaultConnected(address(sv)) && !vh.isPendingDisconnect(address(sv)) && vh.liabilityShares(address(sv)) > 0) ==>
    vh.isVaultHealthy(address(sv))

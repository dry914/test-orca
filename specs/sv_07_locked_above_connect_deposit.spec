# Property: When a vault is connected and not pending disconnect, the locked amount
# must be at least max(CONNECT_DEPOSIT, liability-based safety buffer).
#
# The full invariant computes:
#   minimum_safety_buffer = (liabilityStETH * 10000) / (10000 - forcedRebalanceThresholdBP)
#   locked >= max(CONNECT_DEPOSIT, minimum_safety_buffer)
#
# This V spec expresses the weaker but essential bound: locked >= CONNECT_DEPOSIT (1 ether).
# The safety buffer depends on dynamic Lido share-rate conversion and per-vault threshold
# parameters.
#
# Derived from: fuzz_pr_1570/test/0.8.25/invariant-fuzzing/StakingVaultsFuzzing.t.sol
#   function invariant_07_locked_cannot_be_less_than_slashing_connected_reserve()

vars: VaultHub vh, StakingVault sv
inv: (vh.isVaultConnected(address(sv)) && !vh.isPendingDisconnect(address(sv))) ==>
    vh.locked(address(sv)) >= 1000000000000000000

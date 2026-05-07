# Property: For every connected vault, its VaultHub connection parameters must match
# the corresponding tier parameters registered in the OperatorGrid.
#
# The original invariant checks six fields for each connected vault:
#   - shareLimit (connection <= tier)
#   - reserveRatioBP (equal)
#   - forcedRebalanceThresholdBP (equal)
#   - infraFeeBP (equal)
#   - liquidityFeeBP (equal)
#   - reservationFeeBP (equal)
#
# This V spec checks that the connection's shareLimit does not exceed the
# OperatorGrid's effective share limit for the vault, that the reserve ratio
# and forced rebalance threshold match, and that infra / liquidity / reservation
# fee basis points match the tier (full parity with Foundry invariant5).
#
# Derived from: fuzz_pr_1570/test/0.8.25/invariant-fuzzing/MultiStakingVaultFuzzing.t.sol
#   function invariant5_vault_connection_info()
#
# Struct field index substitutions:
#   VaultConnection.shareLimit = [1]
#   VaultConnection.reserveRatioBP = [4]
#   VaultConnection.forcedRebalanceThresholdBP = [5]
#   vaultTierInfo().shareLimit = [2]
#   vaultTierInfo().reserveRatioBP = [3]
#   vaultTierInfo().forcedRebalanceThresholdBP = [4]
#   vaultTierInfo().infraFeeBP = [5]
#   vaultTierInfo().liquidityFeeBP = [6]
#   vaultTierInfo().reservationFeeBP = [7]
#   VaultConnection.infraFeeBP = [6]
#   VaultConnection.liquidityFeeBP = [7]
#   VaultConnection.reservationFeeBP = [8]

vars: VaultHub vh, OperatorGrid og, StakingVault sv
inv: vh.isVaultConnected(address(sv)) ==>
    vh.vaultConnection(address(sv))[1] <= og.vaultTierInfo(address(sv))[2] &&
    vh.vaultConnection(address(sv))[4] = og.vaultTierInfo(address(sv))[3] &&
    vh.vaultConnection(address(sv))[5] = og.vaultTierInfo(address(sv))[4] &&
    vh.vaultConnection(address(sv))[6] = og.vaultTierInfo(address(sv))[5] &&
    vh.vaultConnection(address(sv))[7] = og.vaultTierInfo(address(sv))[6] &&
    vh.vaultConnection(address(sv))[8] = og.vaultTierInfo(address(sv))[7]

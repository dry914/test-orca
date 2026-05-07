# Property: Amount of Lido fees that can be settled immediately must not exceed
# total unsettled fees reported by obligations().
#
# VaultHub.obligations(_vault)[1] is feesToSettle (unsettled Lido fees in wei).
# settleableLidoFeesValue may be lower when funds are blocked for locks/redemptions.
#
# Derived from: fee accounting consistency (no "settleable" slice larger than debt).

vars: VaultHub vh, StakingVault sv
inv: vh.isVaultConnected(address(sv)) ==>
    vh.settleableLidoFeesValue(address(sv)) <= vh.obligations(address(sv))[1]

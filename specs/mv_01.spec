# Property: No vault's liability shares should exceed its own connection share limit.
# In the multi-vault setting, this must hold for every vault simultaneously.
#
# Derived from: fuzz_pr_1570/test/0.8.25/invariant-fuzzing/MultiStakingVaultFuzzing.t.sol
#   function invariant1_vault_liability_below_share_limit()
#
# Struct field index substitutions:
#   VaultConnection.shareLimit = [1]

vars: VaultHub vh, StakingVault sv
inv: vh.liabilityShares(address(sv)) <= vh.vaultConnection(address(sv))[1]

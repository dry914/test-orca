# Property: Liability shares should never exceed the connection share limit.
# For any connected vault, the total minted liability shares must stay within the
# share limit configured in the vault's VaultHub connection parameters.
#
# Derived from: fuzz_pr_1570/test/0.8.25/invariant-fuzzing/StakingVaultsFuzzing.t.sol
#   function invariant_06_liabilityshares_should_never_be_greater_than_connection_sharelimit()
#
# Struct field index substitutions:
#   VaultConnection.shareLimit = [1]

vars: VaultHub vh, StakingVault sv
inv: vh.liabilityShares(address(sv)) <= vh.vaultConnection(address(sv))[1]

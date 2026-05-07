# Property: ETH notionals for minted liability shares (round-up) must not exceed
# the vault's accounted total value while the vault is connected with liability.
#
# Uses Lido's conservative round-up conversion so "worst case" ETH owed on shares
# stays within VaultHub totalValue — core per-vault solvency / backing.
#
# Derived from: economic safety (complements sv_05 totalValue <= on-chain balance).

vars: VaultHub vh, StakingVault sv, Lido lido
inv: (vh.isVaultConnected(address(sv)) && vh.liabilityShares(address(sv)) > 0) ==>
    lido.getPooledEthBySharesRoundUp(vh.liabilityShares(address(sv))) <= vh.totalValue(address(sv))

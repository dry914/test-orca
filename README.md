# PR 1570 Fuzzing Setup

This directory is the Orca **local deployment** layout for the Lido staking vaults system from PR 1570: `hints/`, `specs/`, and `onchain-deployment.json` live here; the fuzzing run configuration (`config.json`, `project.csv`) lives one level up in [`1570_fuzzing/`](../). It is paired with the Foundry-based invariant fuzzing tests in `fuzz_pr_1570/test/0.8.25/invariant-fuzzing/`.

When running Orca with this folder as the working directory, [`../config.json`](../config.json) sets `"hints_path": "hints"` so Orca loads [`hints/`](hints/) and checks invariants from [`specs/`](specs/).

## Contracts Under Test

The fuzzing targets the core staking vault infrastructure deployed on a mainnet fork (block 24779995). Proxy addresses match [`../project.csv`](../project.csv):

| Contract | Address | Description |
|---|---|---|
| **VaultHub** | `0x1d201BE093d847f6446530Efb0E8Fb426d176709` | Central hub that manages vault connections, minting/burning of stETH shares backed by vault collateral, and enforces health/rebalancing invariants. |
| **OperatorGrid** | `0xC69685E89Cefc327b43B7234AC646451B27c544d` | Manages tiers and groups for node operators, enforcing per-tier and per-group share limits and fee parameters for connected vaults. |
| **Lido** | `0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84` | Core stETH token contract. Interacted with for share minting, burning, and ETH/share conversions. |
| **LazyOracle** | `0x5DB427080200c235F2Ae8Cd17A7be87921f7AD6c` | Oracle contract that accepts vault reports (total value, fees, liability shares) and applies them after a quarantine period. |
| **StakingVault** (x3) | `0x6d41b27087bba7aa9df685866f834af91fad1472`, `0x2814c751847730433c13f74de1e234f8d230853e`, `0x62e0d92cf7b8752b5292b9bcbbace4cfa1633428` | Individual staking vault instances that hold ETH, track deposits/withdrawals via `inOutDelta`, and are managed through VaultHub. |
| **Dashboard** (x3) | `0x4DbF30678DeB96503997a7C79fB6A74f6B809363`, `0x7615Dc44A32993146015eF7F7d2989B02f2DF0B7`, `0xAde0D2c3C75BCbC04cD0C9055b21d0A4B41Ba108` | User-facing management interface for each vault, handling role-based permissions, validator operations, and tier changes. |

[`vault_hub_vault_addresses.hint`](hints/vault_hub_vault_addresses.hint) and [`operator_grid_change_tier.hint`](hints/operator_grid_change_tier.hint) also allowlist a fourth fork vault address, `0x750b07d95802bb81be1a09b002410212ee45c560` (see [`../full_project.csv`](../full_project.csv)); it is not listed in `project.csv` for this deployment’s ABI rows, so Orca may treat it only where hints supply concrete calldata.

## User Addresses

Seven user addresses are configured in [`../config.json`](../config.json), all with zero initial private key (meaning Orca controls them freely for fuzzing). These addresses are chosen to cover the distinct privilege levels present in the system:

| Address | Role |
|---|---|
| `0x7e5f4552091a69125d5dfcb7b8c2659029395bdf` | Anvil default account #1 (generic user / vault funder) |
| `0x3e40D73EB977Dc6a537aF587D48316feE66E9C8c` | Vault owner / Dashboard admin for one of the vaults |
| `0x852deD011285fe67063a08005c71a85690503Cee` | Vault owner / Dashboard admin for another vault |
| `0x4ca5B264B82224c963a939a6a0A99C14C944Dca9` | Node operator account |
| `0x559143dDaA218EC5836A35b6cDf8eB8e6c5cd7bd` | OperatorGrid registry / admin role holder |
| `0xC28317c7F9e4aEE13931a61D4e36e93d9481B298` | VaultHub privileged role holder (VAULT_MASTER / VALIDATOR_EXIT) |
| `0x4508B5cf2B72101e58cd029bC9004C81a5064ca9` | LazyOracle / accounting oracle reporter |

The diversity of addresses ensures the fuzzer explores interactions from different trust levels (vault owners, node operators, protocol admins, oracle reporters, and unprivileged users) to catch access-control violations and cross-role edge cases.

## Function Blacklist

The `fuzzing_blacklist` in [`../config.json`](../config.json) excludes functions from being called directly by the fuzzer. These fall into several categories:

### StakingVault blacklisted functions

All StakingVault external functions are blacklisted. When a vault is connected to VaultHub, it is owned by VaultHub, and all user-facing operations (fund, withdraw, mint, burn, rebalance) must go through VaultHub or Dashboard. Calling StakingVault functions directly would bypass the VaultHub accounting layer and produce unrealistic states. Functions like `initialize`, `ossify`, `depositToBeaconChain`, and `depositFromStaged` are infrastructure/lifecycle operations that are either one-time setup calls or require off-chain beacon chain coordination not modeled in the fuzzer.

### Lido blacklisted functions

All Lido mutative functions are blacklisted. The Lido contract is treated as a fixed external dependency (initialized with mainnet-like state: ~7.8M total shares, ~9.4M total pooled ETH). Allowing the fuzzer to call `mintShares`, `burnShares`, `resume`, `stop`, `deposit`, or reward-processing functions would alter the global stETH share price and produce states not representative of the vault subsystem's behavior in isolation. The stETH exchange rate is intentionally held constant to isolate vault-specific invariants.

### VaultHub blacklisted functions

Most VaultHub functions are blacklisted because they are meant to be reached **through the hints and guided call sequences** rather than called randomly. Key reasons:
- `initialize`, `pauseFor`, `pauseUntil`, `resume`: Lifecycle/admin functions that would disrupt the protocol state.
- `connectVault`, `voluntaryDisconnect`, `fund`, `withdraw`, `mintShares`, `burnShares`, `rebalance`: These are the core operations under test, but they require specific preconditions (fresh oracle reports, sufficient balances, correct caller roles). The hints guide the fuzzer to call these with valid parameters rather than having it blindly guess arguments.
- `applyVaultReport`: Oracle report application is driven by the LazyOracle flow, not called directly on VaultHub.
- `updateConnection`: Only callable by OperatorGrid, never by users directly.
- `transferAndBurnShares`, `transferVaultOwnership`, `collectERC20FromVault`: Administrative operations that would produce unrealistic vault ownership or token states.
- `grantRole`, `requestValidatorExit`, `triggerValidatorWithdrawals`, `proveUnknownValidatorToPDG`, beacon-chain pause/resume, `decreaseInternalizedBadDebt`, and other listed mutators: excluded so exploration stays on the instrumented surface; see [`../config.json`](../config.json) for the full list.
- `renounceRole`, `revokeRole`: Preventing the fuzzer from stripping its own roles mid-run, which would make subsequent calls fail trivially.

### OperatorGrid blacklisted functions

- `initialize`: One-time setup, already performed.
- `grantRole`: Prevents ad-hoc role grants outside the scripted setup.
- `onMintedShares`, `onBurnedShares`, `resetVaultTier`: Callbacks invoked exclusively by VaultHub internally; calling them directly would desync tier accounting.
- `renounceRole`, `revokeRole`: Prevents role stripping.

### LazyOracle blacklisted functions

- `initialize`: Already performed.
- `removeVaultQuarantine`: Admin-only quarantine override that would bypass the normal report flow.
- `renounceRole`, `revokeRole`: Prevents role stripping.

### Dashboard blacklisted functions

- `initialize`, `abandonDashboard`, `connectToVaultHub`, `connectAndAcceptTier`: Lifecycle operations that would disrupt the established vault-hub connections.
- `grantRole`, `grantRoles`, `revokeRole`, `revokeRoles`, `renounceRole`: Prevents the fuzzer from altering Dashboard permissions in ways that make subsequent guided calls fail.
- `proveUnknownValidatorsToPDG`: PDG path not modeled for random exploration here.
- `setConfirmExpiry`: Administrative setting that doesn't affect the core invariants.

## Hints

Hints in [`hints/`](hints/) guide the fuzzer toward valid call sequences with realistic parameters. Each file below is loaded according to [`../config.json`](../config.json) (`"hints_path": "hints"`).

### VaultHub (`vault_hub_*.hint`)

| Hint | Purpose |
|---|---|
| [`vault_hub_vault_addresses.hint`](hints/vault_hub_vault_addresses.hint) | Restricts VaultHub vault arguments to a fixed fork allowlist (including paired vaults in `socializeBadDebt`); supplies 48-byte `pubkeys` for `forceValidatorExit`. |

### OperatorGrid (`operator_grid_*.hint`)

| Hint | Purpose |
|---|---|
| [`operator_grid_register_tiers.hint`](hints/operator_grid_register_tiers.hint) | Keeps `tierParams` for `registerTiers` within expected numeric bounds (reserve ratio, force balance ratio, fee BPs). |
| [`operator_grid_alter_tiers.hint`](hints/operator_grid_alter_tiers.hint) | Restricts `tierIDs` for `alterTiers` to `[0, 165]` and applies the same style of bounded `tierParams`. |
| [`operator_grid_change_tier.hint`](hints/operator_grid_change_tier.hint) | Restricts `changeTier` to the same vault allowlist as above and `tierID` to `[1, 165]`. |

### Dashboard (`dashboard_*.hint`)

| Hint | Purpose |
|---|---|
| [`dashboard_burn_shares.hint`](hints/dashboard_burn_shares.hint) | Reduces `burnShares(shares)` modulo \(2^{128}\) so the argument fits the uint128 expectation. |
| [`dashboard_connect_and_accept_tier.hint`](hints/dashboard_connect_and_accept_tier.hint) | Restricts `connectAndAcceptTier` `tierID` to `[0, 165]` (valid tier range plus headroom for fuzzing). |
| [`dashboard_change_tier.hint`](hints/dashboard_change_tier.hint) | Same `tierID` bound for `changeTier`. |
| [`dashboard_request_validator_exit.hint`](hints/dashboard_request_validator_exit.hint) | Sets `requestValidatorExit` keys to exactly 48 random bytes (one pubkey). |
| [`dashboard_trigger_withdrawals.hint`](hints/dashboard_trigger_withdrawals.hint) | Sets `triggerValidatorWithdrawals` `pubkeys` to 48 random bytes. |

## Invariant Specs

Specs in [`specs/`](specs/) are derived from the Foundry invariant tests and encode the properties Orca checks after every transaction.

### Single-vault properties (`sv_*`)

| Spec | Property |
|---|---|
| `sv_01` | Staking vault should never go below the rebalance threshold (`healthShortfallShares` is zero). |
| `sv_02` | Dynamic total value (including `inOutDelta` adjustments) should never underflow. |
| `sv_03` | `forceRebalance` should not revert when the vault has available balance and outstanding health shortfall. |
| `sv_04` | `forceValidatorExit` should not revert when the vault has an obligations shortfall. |
| `sv_05` | VaultHub `totalValue` for the vault must not exceed the vault contract’s on-chain ETH balance (oracle-processed TV bounded by physical balance). |
| `sv_06` | Liability shares must not exceed the connection share limit. |
| `sv_07` | When connected and not pending disconnect, locked amount must be at least the connect deposit (weaker bound aligned with the Foundry invariant). |
| `sv_08` | Withdrawable value must be at most total value minus locked amount and unsettled obligation fees. |
| `sv_09` | Settleable Lido fees must not exceed unsettled fees from `obligations` (`feesToSettle`). |
| `sv_10` | When connected, not pending disconnect, and liability is non-zero, `isVaultHealthy` must hold (forced rebalance health threshold). |
| `sv_11` | ETH from liability shares (Lido round-up) must not exceed `totalValue` while the vault is connected with non-zero liability. |

### Multi-vault properties (`mv_*`)

| Spec | Property |
|---|---|
| `mv_01` | No vault's liability shares may exceed its own connection share limit. |
| `mv_02` | Each tier’s liability shares must not exceed the node operator group’s share limit (necessary per-tier relaxation of the group sum invariant). |
| `mv_03` | Each vault’s liability shares must not exceed its tier’s tracked `liabilityShares` (necessary per-vault relaxation of tier sum consistency). |
| `mv_04` | Default tier (tier 0) aggregate liability shares must not exceed that tier’s share limit. |
| `mv_05` | For each connected vault, VaultHub connection fields match OperatorGrid tier data (connection `shareLimit` capped by tier; reserve ratio, forced rebalance threshold, and infra/liquidity/reservation fee BPs equal the tier). |

### LazyOracle properties (`lo_*`)

| Spec | Property |
|---|---|
| `lo_01` | Pending `quarantineValue` for a vault must not exceed that vault’s on-chain ETH balance. |

# OrCa Showcase on Lido v3

Minimal setup for running the [OrCa](https://docs.audithub.dev/orca/) fuzzer (Veridise / AuditHub) against Lido v3 on a mainnet fork. Demonstrates three showcase scenarios: liveness under fairness, sequence-coupling, and SMT-quantified state invariants.

## Layout

```
specs/                       # *.spec — invariants in the [V] DSL
hints/                       # *.hint — argument biasing for the fuzzer
script/OrCa.s.sol            # Foundry setup script (impersonate + overlay + prefund)
src/OracleReportRunner.sol   # helper: wraps Accounting.simulateOracleReport →
                             #   handleOracleReport into a single external entry
src/Dummy.sol                # placeholder (forge script requires ≥ 1 deployment)
onchain.deployment.json      # ABIs for every target + the users list
orca-fuzzing-targets.json    # contracts under fuzz
orca-fuzzing-blacklist.json  # functions excluded from random fuzz
ah_runner.sh                 # entrypoint: zip → upload → run OrCa → fetch artifacts
foundry.toml                 # via_ir enabled (required by the runner)
.env.example                 # template for AuditHub creds; .env is git-ignored
```

## Prerequisites

- **Python ≥ 3.12** — the `audithub-client` package wheels are built for 3.12+ only.
- **Foundry** (`forge`) — for the setup script and the `via_ir` build.
- **AuditHub** account + OIDC credentials (see the `.env` section below).

## Setup

```bash
# 1. Python venv + ah CLI
python3.13 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install audithub-client

# 2. Foundry deps + build (via_ir is required, already enabled in foundry.toml)
forge install
forge build

# 3. AuditHub credentials
cp .env.example .env
# Fill in the values inside .env (see the table below)
```

## `.env` — what goes where

| Variable | Where to get it |
|---|---|
| `AUDITHUB_ORGANIZATION_ID` | integer; visible in your organization URL in the AuditHub UI, or via `ah get-my-organizations` |
| `AUDITHUB_PROJECT_ID` | integer; project URL `https://app.audithub.dev/.../projects/<N>` |
| `AUDITHUB_BASE_URL` | typically `https://app.audithub.dev` |
| `AUDITHUB_OIDC_CONFIGURATION_URL` | for prod: `https://sso.veridise.com/auth/realms/veridise/.well-known/openid-configuration` (the placeholder in `.env.example` may be stale — verify that `ah` authenticates successfully) |
| `AUDITHUB_OIDC_CLIENT_ID` | OIDC client from the AuditHub UI → organization → API access |
| `AUDITHUB_OIDC_CLIENT_SECRET` | secret of the same client |

Sanity check after filling in:

```bash
set -a; source .env; set +a
ah get-my-profile
# Should print a JSON blob with your email and id. If not, creds/URLs are wrong.
```

## Running

With venv active (or `AH=` set to the absolute path in `ah_runner.sh:20`):

```bash
./ah_runner.sh
```

The script will:

1. **`create-version-via-local-archive`** — zip the project (excluding `.git`, `out`, `cache`, `.env`) and upload it to AuditHub.
2. **`start-orca-task`** with the flags:
   - `--embedded_specs specs/*.spec` — every invariant.
   - `--embedded-hints hints/*.hint` — every hint.
   - `--auxiliary-deployment-script script/OrCa.s.sol` — setup.
   - `--on-chain --deployment-info-file onchain.deployment.json` — ABIs + users.
   - `--fuzz_targets` / `--fuzzing_blacklist` — parsed from the two JSON files (`orca-fuzzing-{targets,blacklist}.json`).
3. **`monitor-task`** — streams progress over WebSocket until the task finishes.
4. **`download-artifact`** — downloads `call_metrics.json` into the project root.

Artifacts available in the AuditHub UI: `call_metrics.json`, `findings.json`, `lcov.info`.

## Tweakable parameters in `ah_runner.sh`

Edited at the top of the file:

| Variable | Current | Effect |
|---|---|---|
| `TIMEOUT` | `"120"` | seconds for the OrCa fuzzing stage (recommended: `120` for smoke, `600`/`1800` for a real run) |
| `FORK_BLOCK_NUMBER` | `"25088391"` | pin a mainnet block; `"null"` = latest. On `latest` we observed mainnet drift breaking `handleOracleReport` between back-to-back runs, so pinning is recommended. |
| `FORK_NETWORK` | `"mainnet"` | fork network |
| `DETECT_REENTRANCY` | `"false"` | reentrancy detector |
| `FUZZ_PURE` | `"false"` | fuzz pure/view functions |

## What `script/OrCa.s.sol` does during setup

1. `anvil_impersonateAccount` + `anvil_setBalance` for the AccountingOracle (`0x852dEd…`) and three Anvil-default users.
2. `anvil_setCode` overlays the AccountingOracle's bytecode with our `OracleReportRunnerImpl` — so the fuzzer can call `oracleRunner.report(...)` directly while `Accounting.handleOracleReport` still sees the legitimate `msg.sender`.
3. `anvil_setCode` overlays the `TokenRateNotifier` (address resolved through the locator) with a no-op `NoopRebaseReceiver` — without this, `handleOracleReport` reverts via the L2-bridge push.
4. Approves stETH from each user on the WithdrawalQueue (needed for `requestWithdrawals`).
5. Pre-submits 100 ETH from every user (provides initial stETH balance so the fuzzer doesn't immediately trip on `BALANCE_EXCEEDED`).
6. Deploys a `Dummy` contract (forge script requires ≥ 1 deployment in broadcast).

## Specs (`specs/`)

- **`spec_01_liveness_under_fairness.spec`** — pillar 1. `fair: [] <> finished(oracleRunner.report)` + `[] (finished(wq.requestWithdrawals) ==> <> finished(wq.claimWithdrawal))`. Liveness under a fair oracle.
- **`spec_03_unclaimed_implies_locked_ether.spec`** — pillar 3. Free variable `reqId`; the SMT solver searches for a violating value of the implication "if an unclaimed finalized request exists, locked ether > 0".
- **`spec_02_transfer_then_claim_recipient.spec.todo`** — pillar 2 (parked; no obvious [V] syntax for "to received ETH" without a helper tracker contract).

## Hints (`hints/showcase.hint`)

Five functions under fuzz: `lido.submit`, `wq.requestWithdrawals`, `oracleRunner.report`, `wq.claimWithdrawal`, `wq.transferFrom`. Inline comments in the file explain the bounds for each argument.

## Local smoke-test of the setup script (without AuditHub)

Useful when editing overlays — verifies that `script/OrCa.s.sol` itself is healthy:

```bash
anvil --fork-url "<MAINNET_RPC>" --fork-block-number 25088391 &
forge script script/OrCa.s.sol \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast --unlocked \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

If the log shows:

```
Installed OracleReportRunnerImpl at AO, runtime bytes: <N>
OracleReportRunner.getLastProcessingRefSlot() -> <num>
Installed NoopRebaseReceiver at <notifier-addr>, bytes: <N>
Dummy deployed at: 0x…
```

— overlays succeeded and the project is ready for AuditHub.

## Results from prior runs

| Metric | Value |
|---|---|
| `oracleRunner.report` | 100% success (on pinned block 25088391) |
| `lido.submit` | ~99% success |
| `wq.requestWithdrawals` | ~17% success (random fuzz; the rest is BALANCE_EXCEEDED / boundary errors) |
| `wq.claimWithdrawal`, `wq.transferFrom` | 0% success — random `_requestId` rarely lands on our NFTs |
| `spec_01`, `spec_03` | `is_valid: True` across every transaction |

## References

- [OrCa Documentation](https://docs.audithub.dev/orca/)
- [AuditHub-Client (PyPI / GitHub)](https://github.com/Veridise/AuditHub-Client)
- [Lido core / mainnet ABIs](https://github.com/lidofinance/core)

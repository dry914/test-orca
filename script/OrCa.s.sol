// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {Dummy} from "../src/Dummy.sol";

interface IAccessControlEnumerable {
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
    function grantRole(bytes32 role, address account) external;
    function hasRole(bytes32 role, address account) external view returns (bool);
    function getRoleMember(bytes32 role, uint256 index) external view returns (address);
    function getRoleMemberCount(bytes32 role) external view returns (uint256);
}

interface IDashboard is IAccessControlEnumerable {
    function FUND_ROLE() external view returns (bytes32);
    function WITHDRAW_ROLE() external view returns (bytes32);
    function MINT_ROLE() external view returns (bytes32);
    function BURN_ROLE() external view returns (bytes32);
    function REBALANCE_ROLE() external view returns (bytes32);
    function PAUSE_BEACON_CHAIN_DEPOSITS_ROLE() external view returns (bytes32);
    function RESUME_BEACON_CHAIN_DEPOSITS_ROLE() external view returns (bytes32);
    function REQUEST_VALIDATOR_EXIT_ROLE() external view returns (bytes32);
    function TRIGGER_VALIDATOR_WITHDRAWAL_ROLE() external view returns (bytes32);
    function VOLUNTARY_DISCONNECT_ROLE() external view returns (bytes32);
    function VAULT_CONFIGURATION_ROLE() external view returns (bytes32);
    function COLLECT_VAULT_ERC20_ROLE() external view returns (bytes32);
    function NODE_OPERATOR_MANAGER_ROLE() external view returns (bytes32);
    function NODE_OPERATOR_FEE_EXEMPT_ROLE() external view returns (bytes32);
    function NODE_OPERATOR_UNGUARANTEED_DEPOSIT_ROLE() external view returns (bytes32);
    function NODE_OPERATOR_PROVE_UNKNOWN_VALIDATOR_ROLE() external view returns (bytes32);
}

interface IVaultHub is IAccessControlEnumerable {
    function VAULT_MASTER_ROLE() external view returns (bytes32);
    function REDEMPTION_MASTER_ROLE() external view returns (bytes32);
    function VALIDATOR_EXIT_ROLE() external view returns (bytes32);
    function BAD_DEBT_MASTER_ROLE() external view returns (bytes32);
    function PAUSE_ROLE() external view returns (bytes32);
    function RESUME_ROLE() external view returns (bytes32);

    struct Int104WithCache {
        int104 value;
        int104 valueOnRefSlot;
        uint48 refSlot;
    }

    struct Report {
        uint104 totalValue;
        int104 inOutDelta;
        uint48 timestamp;
    }

    struct VaultRecord {
        Report report;
        uint96 maxLiabilityShares;
        uint96 liabilityShares;
        Int104WithCache[2] inOutDelta;
        uint128 minimalReserve;
        uint128 redemptionShares;
        uint128 cumulativeLidoFees;
        uint128 settledLidoFees;
    }

    function vaultRecord(address _vault) external view returns (VaultRecord memory);
    function totalValue(address _vault) external view returns (uint256);
    function isVaultConnected(address _vault) external view returns (bool);
    function latestReport(address _vault) external view returns (Report memory);
}

interface IOperatorGrid is IAccessControlEnumerable {
    function REGISTRY_ROLE() external view returns (bytes32);
}

interface ILazyOracle is IAccessControlEnumerable {
    function UPDATE_SANITY_PARAMS_ROLE() external view returns (bytes32);

    function updateReportData(
        uint256 _vaultsDataTimestamp,
        uint256 _vaultsDataRefSlot,
        bytes32 _vaultsDataTreeRoot,
        string memory _vaultsDataReportCid
    ) external;

    function updateVaultData(
        address _vault,
        uint256 _totalValue,
        uint256 _cumulativeLidoFees,
        uint256 _liabilityShares,
        uint256 _maxLiabilityShares,
        uint256 _slashingReserve,
        bytes32[] calldata _proof
    ) external;

    function latestReportData()
        external
        view
        returns (uint256 timestamp, uint256 refSlot, bytes32 treeRoot, string memory reportCid);
}

interface ILidoLocator {
    function accountingOracle() external view returns (address);
}

contract DeploySetup is Script {
    address constant LIDO_LOCATOR = 0xC1d0b3DE6792Bf6b4b37EccdcC24e45978Cfd2Eb;
    address constant VAULT_HUB = 0x1d201BE093d847f6446530Efb0E8Fb426d176709;
    address constant OPERATOR_GRID = 0xC69685E89Cefc327b43B7234AC646451B27c544d;
    address constant LAZY_ORACLE = 0x5DB427080200c235F2Ae8Cd17A7be87921f7AD6c;

    uint256 constant NUM_DASHBOARDS = 3;
    uint256 constant NUM_VAULTS = 4;
    uint256 constant NUM_USERS = 7;

    address[NUM_DASHBOARDS] dashboards = [
        0x4DbF30678DeB96503997a7C79fB6A74f6B809363,
        0x7615Dc44A32993146015eF7F7d2989B02f2DF0B7,
        0xAde0D2c3C75BCbC04cD0C9055b21d0A4B41Ba108
    ];

    address[NUM_VAULTS] vaults = [
        0x6d41b27087BBA7Aa9Df685866F834AF91Fad1472,
        0x750b07D95802bb81Be1a09b002410212Ee45c560,
        0x2814C751847730433c13f74de1e234F8D230853E,
        0x62e0D92cf7B8752b5292B9BCbbacE4cFa1633428
    ];

    address[NUM_USERS] users = [
        0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf,
        0x3e40D73EB977Dc6a537aF587D48316feE66E9C8c,
        0x852deD011285fe67063a08005c71a85690503Cee,
        0x4ca5B264B82224c963a939a6a0A99C14C944Dca9,
        0x559143dDaA218EC5836A35b6cDf8eB8e6c5cd7bd,
        0xC28317c7F9e4aEE13931a61D4e36e93d9481B298,
        0x4508B5cf2B72101e58cd029bC9004C81a5064ca9
    ];

    struct VaultLeafData {
        address vault;
        uint256 totalValue;
        uint256 cumulativeLidoFees;
        uint256 liabilityShares;
        uint256 maxLiabilityShares;
        uint256 slashingReserve;
    }

    /// @dev Broadcast workflow (Anvil fork):
    ///      1. `anvil --fork-url ...` then run with
    ///      2. `forge script ... --rpc-url http://127.0.0.1:8545 --broadcast --unlocked --private-key <any funded dev key>`
    ///      `--unlocked` makes Forge submit `vm.broadcast(addr)` txs via `eth_sendTransaction` (no key for `addr`).
    ///      This script calls `anvil_impersonateAccount` and `anvil_setBalance` on the RPC node for every
    ///      `from` address. `vm.deal` alone does not persist on Anvil, so gas estimation would see 0 ETH.
    ///      Likewise `vm.etch` does not persist into Anvil's state (so dumps/`eth_getCode` ignore it);
    ///      clearing user bytecode uses `anvil_setCode` via `vm.rpc` instead.
    function run() external {
        _prepareAnvilBroadcastAccounts();
        _grantDashboardRoles();
        _grantOperatorGridRoles();
        _grantVaultHubRoles();
        _grantLazyOracleRoles();
        _submitMerkleRootAndUpdateVaults();
        vm.broadcast(address(0x4ca5B264B82224c963a939a6a0A99C14C944Dca9));
        Dummy d = new Dummy(); // Add a deployed contract to avoid "no contracts deployed error"
        _finalizeUserAccountsOnAnvil();
    }

    /// @notice For each `users` entry: empty runtime code (`anvil_setCode`) and balance 1e24 wei (`anvil_setBalance` + `vm.deal`).
    /// @dev See `run` dev comment: `vm.etch` does not persist on Anvil; RPC mirrors `_prepareAnvilBroadcastAccounts`.
    function _finalizeUserAccountsOnAnvil() internal {
        for (uint256 u = 0; u < NUM_USERS; u++) {
            address a = users[u];
            string memory addrJson = string.concat('"', vm.toString(a), '"');
            vm.rpc("anvil_setCode", string.concat("[", addrJson, ",", '"0x"', "]"));
            vm.rpc("anvil_setBalance", string.concat("[", addrJson, ",", '"', _ANVIL_USER_BALANCE_WEI_HEX, '"', "]"));
            vm.deal(a, 10 ** 24);
        }
    }

    uint256 private constant _MAX_BROADCAST_SENDERS = 24;

    /// @dev 10_000 ether in wei, hex for `anvil_setBalance` (must hit the live Anvil JSON-RPC).
    string private constant _ANVIL_BALANCE_WEI_HEX = "0x21e19e0c9bab2400000";

    /// @dev 1e24 wei, hex for user account funding in `_finalizeUserAccountsOnAnvil`.
    string private constant _ANVIL_USER_BALANCE_WEI_HEX = "0xd3c21bcecceda1000000";

    /// @notice Impersonate every EOA that will appear in `vm.broadcast(address)` so Forge can submit without a private key.
    function _prepareAnvilBroadcastAccounts() internal {
        address[_MAX_BROADCAST_SENDERS] memory senders;
        uint256 n = 0;

        for (uint256 i = 0; i < NUM_DASHBOARDS; i++) {
            IDashboard d = IDashboard(dashboards[i]);
            n = _pushUniqueSender(senders, n, d.getRoleMember(d.DEFAULT_ADMIN_ROLE(), 0));
            bytes32 nomRole = d.NODE_OPERATOR_MANAGER_ROLE();
            if (d.getRoleMemberCount(nomRole) > 0) {
                n = _pushUniqueSender(senders, n, d.getRoleMember(nomRole, 0));
            }
        }

        IOperatorGrid og = IOperatorGrid(OPERATOR_GRID);
        n = _pushUniqueSender(senders, n, og.getRoleMember(og.DEFAULT_ADMIN_ROLE(), 0));

        IVaultHub vh = IVaultHub(VAULT_HUB);
        n = _pushUniqueSender(senders, n, vh.getRoleMember(vh.DEFAULT_ADMIN_ROLE(), 0));

        ILazyOracle lo = ILazyOracle(LAZY_ORACLE);
        n = _pushUniqueSender(senders, n, lo.getRoleMember(lo.DEFAULT_ADMIN_ROLE(), 0));

        n = _pushUniqueSender(senders, n, ILidoLocator(LIDO_LOCATOR).accountingOracle());

        console.log("anvil_impersonateAccount + anvil_setBalance for", n, "broadcast senders");
        for (uint256 i = 0; i < n; i++) {
            address a = senders[i];
            console.log("  Sender", i + 1, ":", a);
            string memory addrJson = string.concat('"', vm.toString(a), '"');
            vm.rpc("anvil_impersonateAccount", string.concat("[", addrJson, "]"));
            vm.rpc("anvil_setBalance", string.concat("[", addrJson, ",", '"', _ANVIL_BALANCE_WEI_HEX, '"', "]"));
            vm.deal(a, 100_000 ether);
        }
    }

    function _pushUniqueSender(address[_MAX_BROADCAST_SENDERS] memory buf, uint256 n, address a)
        private
        pure
        returns (uint256)
    {
        if (a == address(0)) return n;
        for (uint256 i = 0; i < n; i++) {
            if (buf[i] == a) return n;
        }
        require(n < _MAX_BROADCAST_SENDERS, "DeploySetup: too many broadcast senders");
        buf[n] = a;
        return n + 1;
    }

    // ──────────────────────────────────────────────
    //  Role granting
    // ──────────────────────────────────────────────

    function _grantDashboardRoles() internal {
        for (uint256 i = 0; i < NUM_DASHBOARDS; i++) {
            IDashboard d = IDashboard(dashboards[i]);
            console.log("Granting dashboard roles:", dashboards[i]);

            bytes32 adminRole = d.DEFAULT_ADMIN_ROLE();
            address defaultAdmin = d.getRoleMember(adminRole, 0);

            for (uint256 u = 0; u < NUM_USERS; u++) {
                if (!d.hasRole(adminRole, users[u])) {
                    vm.broadcast(defaultAdmin);
                    d.grantRole(adminRole, users[u]);
                }
            }

            // Roles whose admin is DEFAULT_ADMIN_ROLE (standard AccessControl default + explicit setup).
            bytes32[12] memory adminGrantedRoles = [
                d.FUND_ROLE(),
                d.WITHDRAW_ROLE(),
                d.MINT_ROLE(),
                d.BURN_ROLE(),
                d.REBALANCE_ROLE(),
                d.PAUSE_BEACON_CHAIN_DEPOSITS_ROLE(),
                d.RESUME_BEACON_CHAIN_DEPOSITS_ROLE(),
                d.REQUEST_VALIDATOR_EXIT_ROLE(),
                d.TRIGGER_VALIDATOR_WITHDRAWAL_ROLE(),
                d.VOLUNTARY_DISCONNECT_ROLE(),
                d.VAULT_CONFIGURATION_ROLE(),
                d.COLLECT_VAULT_ERC20_ROLE()
            ];

            for (uint256 u = 0; u < NUM_USERS; u++) {
                for (uint256 r = 0; r < adminGrantedRoles.length; r++) {
                    if (!d.hasRole(adminGrantedRoles[r], users[u])) {
                        vm.broadcast(defaultAdmin);
                        d.grantRole(adminGrantedRoles[r], users[u]);
                    }
                }
            }

            // Node-operator roles are administered by NODE_OPERATOR_MANAGER_ROLE, not DEFAULT_ADMIN_ROLE.
            bytes32 nomRole = d.NODE_OPERATOR_MANAGER_ROLE();
            require(d.getRoleMemberCount(nomRole) > 0, "dashboard: no NODE_OPERATOR_MANAGER");
            address nodeOperatorManager = d.getRoleMember(nomRole, 0);

            bytes32[4] memory nomGrantedRoles = [
                nomRole,
                d.NODE_OPERATOR_FEE_EXEMPT_ROLE(),
                d.NODE_OPERATOR_UNGUARANTEED_DEPOSIT_ROLE(),
                d.NODE_OPERATOR_PROVE_UNKNOWN_VALIDATOR_ROLE()
            ];

            for (uint256 u = 0; u < NUM_USERS; u++) {
                for (uint256 r = 0; r < nomGrantedRoles.length; r++) {
                    if (!d.hasRole(nomGrantedRoles[r], users[u])) {
                        vm.broadcast(nodeOperatorManager);
                        d.grantRole(nomGrantedRoles[r], users[u]);
                    }
                }
            }
        }
    }

    function _grantOperatorGridRoles() internal {
        IOperatorGrid og = IOperatorGrid(OPERATOR_GRID);
        console.log("Granting OperatorGrid roles:", OPERATOR_GRID);

        bytes32 adminRole = og.DEFAULT_ADMIN_ROLE();
        address admin = og.getRoleMember(adminRole, 0);

        bytes32[2] memory roles = [adminRole, og.REGISTRY_ROLE()];

        for (uint256 u = 0; u < NUM_USERS; u++) {
            for (uint256 r = 0; r < roles.length; r++) {
                if (!og.hasRole(roles[r], users[u])) {
                    vm.broadcast(admin);
                    og.grantRole(roles[r], users[u]);
                }
            }
        }
    }

    function _grantVaultHubRoles() internal {
        IVaultHub vh = IVaultHub(VAULT_HUB);
        console.log("Granting VaultHub roles:", VAULT_HUB);

        bytes32 adminRole = vh.DEFAULT_ADMIN_ROLE();
        address admin = vh.getRoleMember(adminRole, 0);

        bytes32[7] memory roles = [
            adminRole,
            vh.VAULT_MASTER_ROLE(),
            vh.REDEMPTION_MASTER_ROLE(),
            vh.VALIDATOR_EXIT_ROLE(),
            vh.BAD_DEBT_MASTER_ROLE(),
            vh.PAUSE_ROLE(),
            vh.RESUME_ROLE()
        ];

        for (uint256 u = 0; u < NUM_USERS; u++) {
            for (uint256 r = 0; r < roles.length; r++) {
                if (!vh.hasRole(roles[r], users[u])) {
                    vm.broadcast(admin);
                    vh.grantRole(roles[r], users[u]);
                }
            }
        }
    }

    function _grantLazyOracleRoles() internal {
        ILazyOracle lo = ILazyOracle(LAZY_ORACLE);
        console.log("Granting LazyOracle roles:", LAZY_ORACLE);

        bytes32 adminRole = lo.DEFAULT_ADMIN_ROLE();
        address admin = lo.getRoleMember(adminRole, 0);

        bytes32[2] memory roles = [adminRole, lo.UPDATE_SANITY_PARAMS_ROLE()];

        for (uint256 u = 0; u < NUM_USERS; u++) {
            for (uint256 r = 0; r < roles.length; r++) {
                if (!lo.hasRole(roles[r], users[u])) {
                    vm.broadcast(admin);
                    lo.grantRole(roles[r], users[u]);
                }
            }
        }
    }

    // ──────────────────────────────────────────────
    //  Merkle tree + oracle report
    // ──────────────────────────────────────────────

    function _submitMerkleRootAndUpdateVaults() internal {
        IVaultHub vh = IVaultHub(VAULT_HUB);
        ILazyOracle oracle = ILazyOracle(LAZY_ORACLE);
        address accountingOracle = ILidoLocator(LIDO_LOCATOR).accountingOracle();

        VaultLeafData[NUM_VAULTS] memory leafData = _readLeafData(vh);

        (bytes32 root, bytes32[NUM_VAULTS] memory leaves, bytes32 H01, bytes32 H23) = _buildTree(leafData);
        bytes32[][] memory proofs = _buildProofs(leaves, H01, H23);

        uint256 reportTimestamp = block.timestamp;
        uint256 refSlot = block.number;

        console.log("Submitting merkle root to LazyOracle");
        vm.broadcast(accountingOracle);
        oracle.updateReportData(reportTimestamp, refSlot, root, "setup-cid");

        for (uint256 i = 0; i < NUM_VAULTS; i++) {
            if (!vh.isVaultConnected(leafData[i].vault)) {
                console.log("Skipping disconnected vault:", leafData[i].vault);
                continue;
            }
            console.log("Updating vault data:", leafData[i].vault);
            // Permissionless on LazyOracle; `from` only needs gas. Uses the single signer from `forge script --broadcast`.
            vm.broadcast();
            oracle.updateVaultData(
                leafData[i].vault,
                leafData[i].totalValue,
                leafData[i].cumulativeLidoFees,
                leafData[i].liabilityShares,
                leafData[i].maxLiabilityShares,
                leafData[i].slashingReserve,
                proofs[i]
            );
        }
    }

    // ──────────────────────────────────────────────
    //  Merkle helpers (OZ sorted-pair hashing)
    // ──────────────────────────────────────────────

    function _readLeafData(IVaultHub vh) internal view returns (VaultLeafData[NUM_VAULTS] memory leafData) {
        for (uint256 i = 0; i < NUM_VAULTS; i++) {
            IVaultHub.VaultRecord memory rec = vh.vaultRecord(vaults[i]);
            leafData[i] = VaultLeafData({
                vault: vaults[i],
                totalValue: vh.totalValue(vaults[i]),
                cumulativeLidoFees: rec.cumulativeLidoFees,
                liabilityShares: rec.liabilityShares,
                maxLiabilityShares: rec.maxLiabilityShares,
                slashingReserve: 0
            });
        }
    }

    function _computeLeaf(VaultLeafData memory d) internal pure returns (bytes32) {
        return keccak256(
            bytes.concat(
                keccak256(
                    abi.encode(
                        d.vault,
                        d.totalValue,
                        d.cumulativeLidoFees,
                        d.liabilityShares,
                        d.maxLiabilityShares,
                        d.slashingReserve
                    )
                )
            )
        );
    }

    function _buildTree(
        VaultLeafData[NUM_VAULTS] memory leafData
    ) internal pure returns (bytes32 root, bytes32[NUM_VAULTS] memory leaves, bytes32 H01, bytes32 H23) {
        for (uint256 i = 0; i < NUM_VAULTS; i++) {
            leaves[i] = _computeLeaf(leafData[i]);
        }
        H01 = _hashPair(leaves[0], leaves[1]);
        H23 = _hashPair(leaves[2], leaves[3]);
        root = _hashPair(H01, H23);
    }

    function _buildProofs(
        bytes32[NUM_VAULTS] memory leaves,
        bytes32 H01,
        bytes32 H23
    ) internal pure returns (bytes32[][] memory proofs) {
        proofs = new bytes32[][](NUM_VAULTS);

        proofs[0] = new bytes32[](2);
        proofs[0][0] = leaves[1];
        proofs[0][1] = H23;

        proofs[1] = new bytes32[](2);
        proofs[1][0] = leaves[0];
        proofs[1][1] = H23;

        proofs[2] = new bytes32[](2);
        proofs[2][0] = leaves[3];
        proofs[2][1] = H01;

        proofs[3] = new bytes32[](2);
        proofs[3][0] = leaves[2];
        proofs[3][1] = H01;
    }

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? _efficientHash(a, b) : _efficientHash(b, a);
    }

    function _efficientHash(bytes32 a, bytes32 b) internal pure returns (bytes32 value) {
        assembly {
            mstore(0x00, a)
            mstore(0x20, b)
            value := keccak256(0x00, 0x40)
        }
    }
}

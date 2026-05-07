// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test, console} from "forge-std/Test.sol";

interface IVaultHub {
    struct VaultConnection {
        address owner;
        uint96 shareLimit;
        uint96 vaultIndex;
        uint48 disconnectInitiatedTs;
        uint16 reserveRatioBP;
        uint16 forcedRebalanceThresholdBP;
        uint16 infraFeeBP;
        uint16 liquidityFeeBP;
        uint16 reservationFeeBP;
        bool beaconChainDepositsPauseIntent;
    }

    function isVaultConnected(address vault) external view returns (bool);
    function vaultConnection(address vault) external view returns (VaultConnection memory);
}

/// @dev Selectors must match `OperatorGrid` errors on deployed contracts.
error VaultAlreadySyncedWithTier();
error VaultNotConnected();

interface IOperatorGrid {
    function vaultTierInfo(address vault)
        external
        view
        returns (
            address nodeOperator,
            uint256 tierId,
            uint256 shareLimit,
            uint256 reserveRatioBP,
            uint256 forcedRebalanceThresholdBP,
            uint256 infraFeeBP,
            uint256 liquidityFeeBP,
            uint256 reservationFeeBP
        );
    function syncTier(address vault) external returns (bool);
}

contract VaultConnectionParameterMismatch is Test {
    address constant VAULT_HUB = 0x1d201BE093d847f6446530Efb0E8Fb426d176709;
    address constant OPERATOR_GRID = 0xC69685E89Cefc327b43B7234AC646451B27c544d;

    address[4] vaults = [
        0x6d41b27087BBA7Aa9Df685866F834AF91Fad1472,
        0x750b07D95802bb81Be1a09b002410212Ee45c560,
        0x2814C751847730433c13f74de1e234F8D230853E,
        0x62e0D92cf7B8752b5292B9BCbbacE4cFa1633428
    ];

    IVaultHub vaultHub = IVaultHub(VAULT_HUB);
    IOperatorGrid operatorGrid = IOperatorGrid(OPERATOR_GRID);

    function setUp() public {
        vm.createSelectFork("mainnet", 24779995);
    }

    function test_connectionMatchesTierParams() external view {
        console.log("=== MV-05: Vault connection matches OperatorGrid tier params ===");
        console.log("");

        uint256 mismatches = 0;

        for (uint256 i = 0; i < vaults.length; i++) {
            address vault = vaults[i];
            console.log("--- Vault", i + 1, "---");
            console.log("  address:", vault);

            if (!vaultHub.isVaultConnected(vault)) {
                console.log("  skipped (not connected; spec implication vacuous)");
                console.log("");
                continue;
            }

            mismatches += _mismatchCountForConnectedVault(vault);
            console.log("");
        }

        console.log("=== Summary ===");
        console.log("vaults in list:", vaults.length);
        console.log("mismatch count:", mismatches);

        assertEq(mismatches, 0, "MV-05: vault connection params must match tier (see logs above)");
    }

    function _mismatchCountForConnectedVault(address vault) private view returns (uint256 vaultMismatches) {
        IVaultHub.VaultConnection memory vc = vaultHub.vaultConnection(vault);
        (
            ,
            uint256 tierId,
            uint256 tierShareLimit,
            uint256 tierReserveRatioBP,
            uint256 tierForcedRebalanceThresholdBP,
            uint256 tierInfraFeeBP,
            uint256 tierLiquidityFeeBP,
            uint256 tierReservationFeeBP
        ) = operatorGrid.vaultTierInfo(vault);

        console.log("  tierId:", tierId);
        console.log("  vault index: ", vc.vaultIndex);

        uint256 connShareLimit = uint256(vc.shareLimit);
        if (connShareLimit > tierShareLimit) {
            console.log("  MISMATCH shareLimit: connection > tier (expected connection <= tier)");
            console.log("    connection shareLimit:", connShareLimit);
            console.log("    tier shareLimit:      ", tierShareLimit);
            vaultMismatches++;
        }

        uint256 connReserveRatioBP = uint256(vc.reserveRatioBP);
        if (connReserveRatioBP != tierReserveRatioBP) {
            console.log("  MISMATCH reserveRatioBP");
            console.log("    connection:", connReserveRatioBP);
            console.log("    tier:       ", tierReserveRatioBP);
            vaultMismatches++;
        }

        uint256 connForcedRebalanceThresholdBP = uint256(vc.forcedRebalanceThresholdBP);
        if (connForcedRebalanceThresholdBP != tierForcedRebalanceThresholdBP) {
            console.log("  MISMATCH forcedRebalanceThresholdBP");
            console.log("    connection:", connForcedRebalanceThresholdBP);
            console.log("    tier:       ", tierForcedRebalanceThresholdBP);
            vaultMismatches++;
        }

        uint256 connInfraFeeBP = uint256(vc.infraFeeBP);
        if (connInfraFeeBP != tierInfraFeeBP) {
            console.log("  MISMATCH infraFeeBP");
            console.log("    connection:", connInfraFeeBP);
            console.log("    tier:       ", tierInfraFeeBP);
            vaultMismatches++;
        }

        uint256 connLiquidityFeeBP = uint256(vc.liquidityFeeBP);
        if (connLiquidityFeeBP != tierLiquidityFeeBP) {
            console.log("  MISMATCH liquidityFeeBP");
            console.log("    connection:", connLiquidityFeeBP);
            console.log("    tier:       ", tierLiquidityFeeBP);
            vaultMismatches++;
        }

        uint256 connReservationFeeBP = uint256(vc.reservationFeeBP);
        if (connReservationFeeBP != tierReservationFeeBP) {
            console.log("  MISMATCH reservationFeeBP");
            console.log("    connection:", connReservationFeeBP);
            console.log("    tier:       ", tierReservationFeeBP);
            vaultMismatches++;
        }

        if (vaultMismatches == 0) {
            console.log("  all checks passed for this vault");
        }
    }
}

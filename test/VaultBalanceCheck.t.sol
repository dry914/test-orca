// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test, console} from "forge-std/Test.sol";

interface IVaultHub {
    struct VaultReport {
        uint96 totalValue;
        int96 inOutDelta;
        uint48 timestamp;
    }

    struct VaultRecord {
        VaultReport report;
        // remaining fields omitted; we only need the report
    }

    function totalValue(address vault) external view returns (uint256);
    function isVaultConnected(address vault) external view returns (bool);
    function liabilityShares(address vault) external view returns (uint256);
    function locked(address vault) external view returns (uint256);
    function obligations(address vault) external view returns (uint256 obligationsShares, uint256 obligationsFees);
}

contract VaultBalanceCheck is Test {
    address constant VAULT_HUB = 0x1d201BE093d847f6446530Efb0E8Fb426d176709;

    address[4] vaults = [
        0x6d41b27087BBA7Aa9Df685866F834AF91Fad1472,
        0x750b07D95802bb81Be1a09b002410212Ee45c560,
        0x2814C751847730433c13f74de1e234F8D230853E,
        0x62e0D92cf7B8752b5292B9BCbbacE4cFa1633428
    ];

    IVaultHub vaultHub = IVaultHub(VAULT_HUB);

    function setUp() public {
        vm.createSelectFork("mainnet", 24779995);
    }

    function test_printVaultBalances() external view {
        console.log("=== Staking Vault Balance vs VaultHub Total Value ===");
        console.log("");

        for (uint256 i = 0; i < vaults.length; i++) {
            address vault = vaults[i];
            bool connected = vaultHub.isVaultConnected(vault);
            uint256 ethBalance = vault.balance;
            uint256 hubTotalValue = vaultHub.totalValue(vault);
            uint256 liabilities = vaultHub.liabilityShares(vault);
            uint256 lockedAmt = vaultHub.locked(vault);

            console.log("--- Vault", i + 1, "---");
            console.log("  Address:          ", vault);
            console.log("  Connected:        ", connected);
            console.log("  ETH balance (wei):", ethBalance);
            console.log("  VH totalValue:    ", hubTotalValue);

            if (ethBalance >= hubTotalValue) {
                console.log("  Difference:        ETH balance exceeds totalValue by", ethBalance - hubTotalValue);
            } else {
                console.log("  Difference:        totalValue exceeds ETH balance by", hubTotalValue - ethBalance);
            }

            (uint256 obligShares, uint256 obligFees) = vaultHub.obligations(vault);

            console.log("  Liability shares: ", liabilities);
            console.log("  Locked:           ", lockedAmt);
            console.log("  Oblig. shares:    ", obligShares);
            console.log("  Oblig. fees:      ", obligFees);

            if (hubTotalValue > ethBalance) {
                console.log("  Implied CL bal:   ", hubTotalValue - ethBalance);
            } else {
                console.log("  Implied CL bal:    0 (all value on EL)");
            }
            console.log("");
        }
    }
}

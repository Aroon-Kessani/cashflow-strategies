// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {Vault} from "../src/Vault.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

// Deploys the Vault with the provided mainnet parameters
contract DeployVault is Script {
    function run() external {
        // Constructor params (mainnet)
        address POOL = 0x046dccb728c39F8aa69E47daC0eBDAD8d2CdDfE9;
        IERC20[] memory poolTokens = new IERC20[](2);
        poolTokens[0] = IERC20(0xaD55aebc9b8c03FC43cd9f62260391c13c23e7c0); // cUSDO
        poolTokens[1] = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // USDC
        string memory NAME = "CashFlow-cUSDO-USDC";
        string memory SYMBOL = "CF-cUSDO-USDC";
        address ROUTER = 0xb21A277466e7dB6934556a1Ce12eb3F032815c8A;
        address BATCH_ROUTER = 0x136f1EFcC3f8f88516B9E94110D56FDBfB1778d1;
        address WNATIVE = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH
        address GAUGE = address(0);
        address PSEUDO_MINTER = 0x239e55F427D44C3cc793f49bFB507ebe76638a2b;
        address PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
        address OWNER = 0xD13a8c33eCb4d38FBC1760C7f7F1e1C7b1162739;
        address FEE_RECEIVER = 0xD13a8c33eCb4d38FBC1760C7f7F1e1C7b1162739;

        vm.startBroadcast();
        Vault vault = new Vault(
            POOL,
            poolTokens,
            NAME,
            SYMBOL,
            ROUTER,
            BATCH_ROUTER,
            WNATIVE,
            GAUGE,
            PSEUDO_MINTER,
            PERMIT2,
            OWNER,
            FEE_RECEIVER
        );
        vm.stopBroadcast();

        console2.log("Vault deployed at:", address(vault));
    }
}

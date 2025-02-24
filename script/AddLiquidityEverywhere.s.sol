// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "forge-std/src/Script.sol";
import "@openzeppelin-contracts/token/ERC20/IERC20.sol";

interface IUniswapV2Router {
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);
}

contract AddLiquidityEverywhere is Script {
    function run() external {
        uint256 amount = vm.envUint("AMOUNT");
        address myAddress = vm.envAddress("MY_ADDRESS");
        IUniswapV2Router router = IUniswapV2Router(vm.envAddress("UNISWAP_V2_ROUTER"));
        address[][] memory shortLongPairs = abi.decode(vm.parseJson(vm.envString("SHORT_LONG_PAIRS")), (address[][]));
        uint256 minAmount = (amount * (100 - vm.envUint("SLIPPAGE_PCT"))) / 100;

        vm.startBroadcast();

        for (uint256 i = 0; i < shortLongPairs.length; i++) {
            address shortTokenAddr = shortLongPairs[i][0];
            address longTokenAddr = shortLongPairs[i][1];

            IERC20(shortTokenAddr).approve(address(router), amount);
            IERC20(longTokenAddr).approve(address(router), amount);

            router.addLiquidity(
                shortTokenAddr,
                longTokenAddr,
                amount,
                amount,
                minAmount,
                minAmount,
                myAddress,
                block.timestamp + 600 // 10 min deadline
            );

            console.log("Liquidity added for pair index=%s short=%s long=%s", i, shortTokenAddr, longTokenAddr);
        }

        vm.stopBroadcast();
    }
}

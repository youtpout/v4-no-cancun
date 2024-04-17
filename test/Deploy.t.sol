// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {Counter} from "../src/Counter.sol";
import {HookMiner} from "./utils/HookMiner.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {PoolModifyLiquidityTest} from "v4-core/src/test/PoolModifyLiquidityTest.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {Token} from "../src/Token.sol";

contract DeployTest is Test {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    Counter counter;
    PoolId poolId;
    PoolManager manager;
    PoolKey key;
    PoolModifyLiquidityTest lpRouter;
    PoolSwapTest swapRouter;

    Token MUNI_ADDRESS;
    Token MUSDC_ADDRESS;

    uint160 public constant MIN_PRICE_LIMIT = TickMath.MIN_SQRT_RATIO + 1;
    uint160 public constant MAX_PRICE_LIMIT = TickMath.MAX_SQRT_RATIO - 1;

    bytes constant ZERO_BYTES = new bytes(0);

    address deployer = makeAddr("Deployer");
    address alice = makeAddr("Alice");
    address bob = makeAddr("Bob");
    address charlie = makeAddr("Charlie");
    address daniel = makeAddr("Daniel");

    function deployBytecode(
        bytes memory bytecode
    ) internal returns (address deployedAddress) {
        deployedAddress;
        assembly {
            deployedAddress := create(0, add(bytecode, 0x20), mload(bytecode))
        }

        ///@notice check that the deployment was successful
        require(
            deployedAddress != address(0),
            "YulDeployer could not deploy contract"
        );
    }


    function setUp() public {
        // create pool manage 500k gas max
        manager = new PoolManager(500000);
        lpRouter = new PoolModifyLiquidityTest(manager);
        swapRouter = new PoolSwapTest(manager);

        MUNI_ADDRESS = new Token("MUNI", "MUNI", deployer);
        MUSDC_ADDRESS = new Token("MUSDC", " MUSDC", deployer);

        // Deploy the hook to an address with the correct flags
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG |
                Hooks.AFTER_SWAP_FLAG |
                Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
        );
        (address hookAddress, bytes32 salt) = HookMiner.find(
            address(this),
            flags,
            type(Counter).creationCode,
            abi.encode(address(manager))
        );
        counter = new Counter{salt: salt}(IPoolManager(address(manager)));
        require(
            address(counter) == hookAddress,
            "CounterTest: hook address mismatch"
        );

        address token0 = uint160(address(MUSDC_ADDRESS)) <
            uint160(address(MUNI_ADDRESS))
            ? address(MUSDC_ADDRESS)
            : address(MUNI_ADDRESS);
        address token1 = uint160(address(MUSDC_ADDRESS)) <
            uint160(address(MUNI_ADDRESS))
            ? address(MUNI_ADDRESS)
            : address(MUSDC_ADDRESS);

        // Create the pool
        key = PoolKey(
            Currency.wrap(token0),
            Currency.wrap(token1),
            3000,
            60,
            IHooks(address(counter))
        );
        poolId = key.toId();

        bytes memory hookData = abi.encode(block.timestamp);
        // floor(sqrt(1) * 2^96)
        uint160 startingPrice = 79228162514264337593543950336;
        manager.initialize(key, startingPrice, hookData);

        bytes32 idBytes = PoolId.unwrap(poolId);

        console.log("Pool ID Below");
        console.logBytes32(bytes32(idBytes));

        // Provide liquidity to the pool
        IERC20(token0).approve(address(lpRouter), 1000e18);
        IERC20(token1).approve(address(lpRouter), 1000e18);
        IERC20(token0).approve(address(swapRouter), 1000e18);
        IERC20(token1).approve(address(swapRouter), 1000e18);

        lpRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams(-600, 600, 10_000e18),
            hookData
        );
    }

    function testCounterHooks() public {
        // positions were created in setup()
        assertEq(counter.beforeSwapCount(poolId), 0);
        assertEq(counter.afterSwapCount(poolId), 0);

        // Perform a test swap //
        bool zeroForOne = true;
        int256 amountSpecified = -1e18; // negative number indicates exact input swap!
        BalanceDelta swapDelta = swap(
            key,
            zeroForOne,
            amountSpecified,
            ZERO_BYTES
        );
        // ------------------- //

        assertEq(int256(swapDelta.amount0()), amountSpecified);

        assertEq(counter.beforeSwapCount(poolId), 1);
        assertEq(counter.afterSwapCount(poolId), 1);
    }

    /// @notice Helper function for a simple ERC20 swaps that allows for unlimited price impact
    function swap(
        PoolKey memory _key,
        bool zeroForOne,
        int256 amountSpecified,
        bytes memory hookData
    ) internal returns (BalanceDelta) {
        // allow native input for exact-input, guide users to the `swapNativeInput` function
        bool isNativeInput = zeroForOne && _key.currency0.isNative();
        if (isNativeInput)
            require(
                0 > amountSpecified,
                "Use swapNativeInput() for native-token exact-output swaps"
            );

        uint256 value = isNativeInput ? uint256(-amountSpecified) : 0;

        return
            swapRouter.swap{value: value}(
                _key,
                IPoolManager.SwapParams({
                    zeroForOne: zeroForOne,
                    amountSpecified: amountSpecified,
                    sqrtPriceLimitX96: zeroForOne
                        ? MIN_PRICE_LIMIT
                        : MAX_PRICE_LIMIT
                }),
                PoolSwapTest.TestSettings({
                    withdrawTokens: true,
                    settleUsingTransfer: true,
                    currencyAlreadySent: false
                }),
                hookData
            );
    }
}

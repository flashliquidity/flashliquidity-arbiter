//SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {Governable} from "flashliquidity-acs/contracts/Governable.sol";
import {DexAdapter} from "./DexAdapter.sol";

/**
 * @title UniswapV2Adapter
 * @author Oddcod3 (@oddcod3)
 */
contract UniswapV2Adapter is DexAdapter, Governable {
    using SafeERC20 for IERC20;

    error UniswapV2Adapter__OutOfBound();
    error UniswapV2Adapter__NotRegisteredFactory();
    error UniswapV2Adapter__FactoryAlreadyRegistered();
    error UniswapV2Adapter__InvalidPool();

    struct UniswapV2FactoryData {
        bool isRegistered;
        uint48 feeNumerator;
        uint48 feeDenominator;
    }

    /// @dev Array of Uniswap V2 Factory interfaces that the contract interacts with.
    IUniswapV2Factory[] private s_factories;
    /// @dev A mapping from Uniswap V2 Factory addresses to their respective data structures.
    mapping(address => UniswapV2FactoryData) private s_factoryData;

    constructor(address governor, string memory description) DexAdapter(description) Governable(governor) {}

    /**
     * @dev Registers a new factory in the adapter with specific fee parameters. This function can only be called by the contract's governor.
     * @param factory The address of the UniswapV2 factory to be registered.
     * @param feeNumerator The numerator part of the fee fraction for this factory.
     * @param feeDenominator The denominator part of the fee fraction for this factory.
     * @notice This function will revert with 'UniswapV2Adapter__FactoryAlreadyRegistered' if the factory is already registered.
     *         It sets the factory as registered and stores its fee structure.
     */
    function addFactory(address factory, uint48 feeNumerator, uint48 feeDenominator) external onlyGovernor {
        UniswapV2FactoryData storage factoryData = s_factoryData[factory];
        if (factoryData.isRegistered) revert UniswapV2Adapter__FactoryAlreadyRegistered();
        factoryData.isRegistered = true;
        factoryData.feeNumerator = feeNumerator;
        factoryData.feeDenominator = feeDenominator;
        s_factories.push(IUniswapV2Factory(factory));
    }

    /**
     * @dev Removes a factory from the list. This function can only be called by the contract's governor.
     * @param factoryIndex The index of the factory in the s_factories array to be removed.
     * @notice If the factoryIndex is out of bounds of s_factories array, the function will revert with 'UniswapV2Adapter__OutOfBound'.
     *         This function deletes the factory's data and removes it from the s_factories array.
     * @notice Care must be taken to pass the correct factoryIndex, as an incorrect index can result in the removal of the wrong factory.
     */
    function removeFactory(uint256 factoryIndex) external onlyGovernor {
        uint256 factoriesLen = s_factories.length;
        if (factoriesLen == 0 || factoryIndex >= factoriesLen) revert UniswapV2Adapter__OutOfBound();
        delete s_factoryData[address(s_factories[factoryIndex])];
        if (factoryIndex < factoriesLen - 1) {
            s_factories[factoryIndex] = s_factories[factoriesLen - 1];
        }
        s_factories.pop();
    }

    /// @inheritdoc DexAdapter
    function _swap(
        address tokenIn,
        address tokenOut,
        address to,
        uint256 amount0Out,
        uint256 amount1Out,
        bytes memory extraArgs
    ) internal override {
        IUniswapV2Factory factory = IUniswapV2Factory(abi.decode(extraArgs, (address)));
        if (!s_factoryData[address(factory)].isRegistered) revert UniswapV2Adapter__NotRegisteredFactory();
        address targetPool = factory.getPair(tokenIn, tokenOut);
        uint256 amountIn = amount0Out;
        (amount0Out, amount1Out) = tokenIn < tokenOut ? (uint256(0), amount1Out) : (amount1Out, uint256(0));
        if (targetPool == address(0)) revert UniswapV2Adapter__InvalidPool();
        IERC20(tokenIn).safeTransferFrom(msg.sender, targetPool, amountIn);
        IUniswapV2Pair(targetPool).swap(amount0Out, amount1Out, to, new bytes(0));
    }

    /// @inheritdoc DexAdapter
    function _getMaxOutput(address tokenIn, address tokenOut, uint256 amountIn)
        internal
        view
        override
        returns (uint256 maxOutput, bytes memory extraArgs)
    {
        IUniswapV2Factory targetFactory;
        UniswapV2FactoryData memory factoryData;
        address targetPool;
        uint256 factoriesLen = s_factories.length;
        uint256 tempOutput;
        bool zeroToOne = tokenIn < tokenOut;
        for (uint256 i; i < factoriesLen;) {
            targetFactory = s_factories[i];
            targetPool = targetFactory.getPair(tokenIn, tokenOut);
            if (targetPool != address(0)) {
                factoryData = s_factoryData[address(targetFactory)];
                tempOutput =
                    _getAmountOut(targetPool, amountIn, factoryData.feeNumerator, factoryData.feeDenominator, zeroToOne);
                if (tempOutput > maxOutput) {
                    maxOutput = tempOutput;
                    extraArgs = abi.encode(address(targetFactory));
                }
            }
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Calculates the amount of output tokens that can be obtained from a given input amount for a swap operation in a Uniswap V2 pool, considering the pool's reserves and fee structure.
     * @param targetPool The address of the Uniswap V2 pool.
     * @param amountIn The amount of input tokens to be swapped.
     * @param feeNumerator The numerator part of the fee fraction for the swap.
     * @param feeDenominator The denominator part of the fee fraction for the swap.
     * @param zeroToOne A boolean flag indicating the direction of the swap (true for swapping token0 to token1, false for token1 to token0).
     * @return amountOut The amount of output tokens that can be received from the swap.
     * @notice This function computes the output amount by applying the Uniswap V2 formula, taking into account the current reserves of the pool and the specified fee structure.
     */
    function _getAmountOut(
        address targetPool,
        uint256 amountIn,
        uint48 feeNumerator,
        uint48 feeDenominator,
        bool zeroToOne
    ) private view returns (uint256 amountOut) {
        uint256 amountInWithFee;
        (uint256 reserveIn, uint256 reserveOut,) = IUniswapV2Pair(targetPool).getReserves();
        (reserveIn, reserveOut) = zeroToOne ? (reserveIn, reserveOut) : (reserveOut, reserveIn);
        if (reserveIn > 0 && reserveOut > 0) {
            amountInWithFee = amountIn * feeNumerator;
            amountOut = (amountInWithFee * reserveOut) / ((reserveIn * feeDenominator) + amountInWithFee);
        }
    }

    /**
     * @dev Retrieves details of a specific factory identified by its index in the 's_factory' array.
     * @param factoryIndex The index of the factory in the 's_factories' array.
     * @return factory The address of the factory at the specified index.
     * @return feeNumerator The numerator part of the fee fraction associated with this factory.
     * @return feeDenominator The denominator part of the fee fraction associated with this factory.
     * @notice The function will return the address of the factory and its fee structure.
     *         It is important to ensure that the factoryIndex is within the bounds of the array to avoid out-of-bounds errors.
     */
    function getFactoryAtIndex(uint256 factoryIndex)
        external
        view
        returns (address factory, uint48 feeNumerator, uint48 feeDenominator)
    {
        factory = address(s_factories[factoryIndex]);
        UniswapV2FactoryData memory factoryData = s_factoryData[address(factory)];
        feeNumerator = factoryData.feeNumerator;
        feeDenominator = factoryData.feeDenominator;
    }

    /// @return factoriesLength The number of factories currently registered
    function allFactoriesLength() external view returns (uint256) {
        return s_factories.length;
    }
}

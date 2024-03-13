//SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3SwapCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import {IQuoterV2} from "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";
import {Governable} from "flashliquidity-acs/contracts/Governable.sol";
import {DexAdapter} from "./DexAdapter.sol";

/**
 * @title UniswapV3Adapter
 * @author Oddcod3 (@oddcod3)
 */
contract UniswapV3Adapter is DexAdapter, Governable, IUniswapV3SwapCallback {
    using SafeERC20 for IERC20;

    error UniswapV3Adapter__OutOfBound();
    error UniswapV3Adapter__NotRegisteredFactory();
    error UniswapV3Adapter__FactoryAlreadyRegistered();
    error UniswapV3Adapter__NotAuthorizedPool();
    error UniswapV3Adapter__InvalidPool();
    error UniswapV3Adapter__InvalidAmountDeltas();
    error UniswapV3Adapter__InsufficentOutput();

    struct UniswapV3FactoryData {
        bool isRegistered;
        address quoter; // on-chain, view quoter
        uint24[] fees;
    }

    struct SwapCallbackData {
        address sender;
        address tokenIn;
        address tokenOut;
        address factory;
        uint24 fee;
    }

    /// @dev The minimum tick that may be passed to #getSqrtRatioAtTick computed from log base 1.0001 of 2**-128
    uint160 private constant MIN_SQRT_RATIO = 4295128739;
    /// @dev The maximum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MAX_TICK)
    uint160 private constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

    /// @dev Array of Uniswap V3 Factory interfaces used by the contract.
    IUniswapV3Factory[] private s_factories;
    /// @dev This mapping holds information about each registered factory, such as fee tiers and associated quoters.
    mapping(address => UniswapV3FactoryData) private s_factoryData;

    constructor(address governor, string memory description) DexAdapter(description) Governable(governor) {}

    /**
     * @dev Registers a new Uniswap V3 factory in the system along with its quoter and fee. This function can only be executed by the contract's governor.
     * @param factory The address of the Uniswap V3 factory to be registered.
     * @param quoter The address of the quoter associated with this factory.
     * @param fees The fees array associated with the factory.
     * @notice If the factory is already registered, the function will revert with 'UniswapV3Adapter__FactoryAlreadyRegistered'.
     *         The factory's data, including its fee and quoter, is stored, and the factory is added to the 's_factories' array.
     */
    function addFactory(address factory, address quoter, uint24[] memory fees) external onlyGovernor {
        UniswapV3FactoryData storage factoryData = s_factoryData[factory];
        if (factoryData.isRegistered) revert UniswapV3Adapter__FactoryAlreadyRegistered();
        factoryData.isRegistered = true;
        factoryData.quoter = quoter;
        factoryData.fees = fees;
        s_factories.push(IUniswapV3Factory(factory));
    }

    /**
     * @dev Removes a factory from the 's_factories' array. This function can only be executed by the contract's governor.
     * @param factoryIndex The index of the factory to be removed.
     * @notice If the factoryIndex is out of bounds, the function will revert with 'UniswapV3Adapter__OutOfBound'.
     *         This function deletes the factory's data and removes it from the 's_factories' array.
     * @notice Care must be taken to pass the correct factoryIndex, as an incorrect index can result in the removal of the wrong factory.
     */
    function removeFactory(uint256 factoryIndex) external onlyGovernor {
        uint256 factoriesLen = s_factories.length;
        if (factoriesLen == 0 || factoryIndex >= factoriesLen) revert UniswapV3Adapter__OutOfBound();
        delete s_factoryData[address(s_factories[factoryIndex])];
        if (factoryIndex < factoriesLen - 1) {
            s_factories[factoryIndex] = s_factories[factoriesLen - 1];
        }
        s_factories.pop();
    }

    /**
     * @dev Adds an array of fee tiers to a registered Uniswap V3 factory's data. This function can only be called by the contract's governor.
     * @param factory The address of the Uniswap V3 factory to which fee tiers are to be added.
     * @param fees An array of fee tiers (uint24) to be added to the factory.
     * @notice This function will revert with 'UniswapV3Adapter__NotRegisteredFactory' if the factory is not already registered.
     *         It appends each fee from the 'fees' array to the factory's data, expanding its fee options.
     */
    function addFactoryFees(address factory, uint24[] memory fees) external onlyGovernor {
        UniswapV3FactoryData storage factoryData = s_factoryData[factory];
        if (!factoryData.isRegistered) revert UniswapV3Adapter__NotRegisteredFactory();
        uint256 feesLen = fees.length;
        for (uint256 i; i < feesLen;) {
            factoryData.fees.push(fees[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Removes a fee tier from a registered Uniswap V3 factory's data at a specified index. This function can only be called by the contract's governor.
     * @param factory The address of the Uniswap V3 factory from which the fee tier is to be removed.
     * @param feeIndex The index of the fee tier in the factory's fees array to be removed.
     * @notice If the factory is not registered, the function will revert with 'UniswapV3Adapter__NotRegisteredFactory'.
     *         If the feeIndex is out of bounds, it will revert with 'UniswapV3Adapter__OutOfBound'.
     *         The function replaces the fee at feeIndex with the last fee in the array and then removes the last element, maintaining array integrity.
     */
    function removeFactoryFee(address factory, uint256 feeIndex) external onlyGovernor {
        UniswapV3FactoryData storage factoryData = s_factoryData[factory];
        if (!factoryData.isRegistered) revert UniswapV3Adapter__NotRegisteredFactory();
        uint256 feesLen = factoryData.fees.length;
        if (feesLen == 0 || feeIndex >= feesLen) revert UniswapV3Adapter__OutOfBound();
        if (feeIndex < feesLen - 1) {
            factoryData.fees[feeIndex] = factoryData.fees[feesLen - 1];
        }
        factoryData.fees.pop();
    }

    /// @inheritdoc IUniswapV3SwapCallback
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata callbackData)
        external
        override
    {
        if (amount0Delta <= 0 && amount1Delta <= 0) revert UniswapV3Adapter__InvalidAmountDeltas();
        SwapCallbackData memory data = abi.decode(callbackData, (SwapCallbackData));
        if (!s_factoryData[data.factory].isRegistered) revert UniswapV3Adapter__NotRegisteredFactory();
        if (msg.sender != IUniswapV3Factory(data.factory).getPool(data.tokenIn, data.tokenOut, data.fee)) {
            revert UniswapV3Adapter__NotAuthorizedPool();
        }
        uint256 amountToPay = amount0Delta > 0 ? uint256(amount0Delta) : uint256(amount1Delta);
        IERC20(data.tokenIn).safeTransferFrom(data.sender, msg.sender, amountToPay);
    }

    /// @inheritdoc DexAdapter
    function _swap(
        address tokenIn,
        address tokenOut,
        address to,
        uint256 amountIn,
        uint256 amountOut,
        bytes memory extraArgs
    ) internal override {
        (address factory, uint24 fee) = abi.decode(extraArgs, (address, uint24));
        if (!s_factoryData[factory].isRegistered) revert UniswapV3Adapter__NotRegisteredFactory();
        bool zeroToOne = tokenIn < tokenOut;
        address targetPool = IUniswapV3Factory(factory).getPool(tokenIn, tokenOut, fee);
        if (targetPool == address(0)) revert UniswapV3Adapter__InvalidPool();
        SwapCallbackData memory callbackData =
            SwapCallbackData({sender: msg.sender, tokenIn: tokenIn, tokenOut: tokenOut, factory: factory, fee: fee});
        (int256 amount0Delta, int256 amount1Delta) = IUniswapV3Pool(targetPool).swap(
            to,
            zeroToOne,
            int256(amountIn),
            zeroToOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1,
            abi.encode(callbackData)
        );
        if (zeroToOne && uint256(-amount1Delta) < amountOut) {
            revert UniswapV3Adapter__InsufficentOutput();
        } else if (!zeroToOne && uint256(-amount0Delta) < amountOut) {
            revert UniswapV3Adapter__InsufficentOutput();
        }
    }

    /// @inheritdoc DexAdapter
    function _getMaxOutput(address tokenIn, address tokenOut, uint256 amountIn)
        internal
        view
        override
        returns (uint256 maxOutput, bytes memory extraArgs)
    {
        uint256 factoriesLen = s_factories.length;
        uint256 tempOutput;
        bytes memory tempExtraArgs;
        IUniswapV3Factory targetFactory;
        UniswapV3FactoryData memory targetFactoryData;
        IQuoterV2.QuoteExactInputSingleParams memory quoterParams = IQuoterV2.QuoteExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            fee: 0,
            sqrtPriceLimitX96: 0
        });
        for (uint256 i = 0; i < factoriesLen;) {
            targetFactory = s_factories[i];
            targetFactoryData = s_factoryData[address(targetFactory)];
            (tempOutput, tempExtraArgs) = _getMaxOutputForFactory(targetFactory, targetFactoryData, quoterParams);
            if (tempOutput > maxOutput) {
                maxOutput = tempOutput;
                extraArgs = tempExtraArgs;
            }
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Calculates the maximum output for a swap operation, considering the different fee tiers of the specified Uniswap V3 factory.
     * @param targetFactory The Uniswap V3 factory interface to be used for the swap.
     * @param targetFactoryData Contains data related to the target factory, including an array of possible fee tiers.
     * @param quoterParams Parameters for the Uniswap V3 quoter, used to estimate the swap output for each fee tier.
     * @return maxOutput The maximum output amount that can be obtained from the swap across all considered fee tiers.
     * @return extraArgs Encoded additional arguments, including the selected factory and fee tier for the optimal swap.
     * @notice This function iterates over the array of fee tiers in the provided factory data,
     *         querying the quoter for each tier to find the best possible swap output. It returns the highest output and the corresponding extra arguments for the optimal swap.
     */
    function _getMaxOutputForFactory(
        IUniswapV3Factory targetFactory,
        UniswapV3FactoryData memory targetFactoryData,
        IQuoterV2.QuoteExactInputSingleParams memory quoterParams
    ) private view returns (uint256 maxOutput, bytes memory extraArgs) {
        uint256 tempOutput;
        bool success;
        bytes memory returnData;
        bytes memory encodedQuoterParams;
        uint24 fee;
        address targetPool;
        for (uint256 i; i < targetFactoryData.fees.length;) {
            fee = targetFactoryData.fees[i];
            targetPool = targetFactory.getPool(quoterParams.tokenIn, quoterParams.tokenOut, fee);
            if (targetPool != address(0)) {
                quoterParams.fee = fee;
                encodedQuoterParams = abi.encodeWithSelector(IQuoterV2.quoteExactInputSingle.selector, quoterParams);
                (success, returnData) = targetFactoryData.quoter.staticcall(encodedQuoterParams);
                if (success) {
                    tempOutput = abi.decode(returnData, (uint256));
                    if (tempOutput > maxOutput) {
                        maxOutput = tempOutput;
                        extraArgs = abi.encode(targetFactory, fee);
                    }
                }
            }
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Retrieves the details of a specific factory, identified by its index.
     * @param factoryIndex The index of the factory in the 's_factories' array.
     * @return factory The address of the factory at the specified index.
     * @return quoter The address of the quoter associated with this factory.
     * @return fees The fees array associated with this factory.
     * @notice The function will return the address of the factory, along with its quoter and fees array.
     *         It is important to ensure that the factoryIndex is within the bounds of the array to avoid out-of-bounds errors.
     */
    function getFactoryAtIndex(uint256 factoryIndex)
        external
        view
        returns (address factory, address quoter, uint24[] memory fees)
    {
        factory = address(s_factories[factoryIndex]);
        UniswapV3FactoryData memory factoryData = s_factoryData[factory];
        quoter = factoryData.quoter;
        fees = factoryData.fees;
    }

    /// @return factoriesLength The number of factories currently registered
    function allFactoriesLength() external view returns (uint256) {
        return s_factories.length;
    }
}

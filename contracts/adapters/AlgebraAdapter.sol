//SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAlgebraFactory} from "../interfaces/IAlgebraFactory.sol";
import {IAlgebraPool} from "../interfaces/IAlgebraPool.sol";
import {IAlgebraSwapCallback} from "../interfaces/IAlgebraSwapCallback.sol";
import {IAlgebraQuoter} from "../interfaces/IAlgebraQuoter.sol";
import {Governable} from "flashliquidity-acs/contracts/Governable.sol";
import {DexAdapter} from "./DexAdapter.sol";

/**
 * @title AlgebraAdapter
 * @author Oddcod3 (@oddcod3)
 */
contract AlgebraAdapter is DexAdapter, Governable, IAlgebraSwapCallback {
    using SafeERC20 for IERC20;

    error AlgebraAdapter__OutOfBound();
    error AlgebraAdapter__NotRegisteredFactory();
    error AlgebraAdapter__FactoryAlreadyRegistered();
    error AlgebraAdapter__NotAuthorizedPool();
    error AlgebraAdapter__InvalidPool();
    error AlgebraAdapter__InvalidAmountDeltas();
    error AlgebraAdapter__InsufficentOutput();

    struct AlgebraFactoryData {
        bool isRegistered;
        address quoter; // on-chain, view quoter
    }

    struct SwapCallbackData {
        address sender;
        address tokenIn;
        address tokenOut;
        address factory;
    }

    /// @dev The minimum tick that may be passed to #getSqrtRatioAtTick computed from log base 1.0001 of 2**-128
    uint160 private constant MIN_SQRT_RATIO = 4295128739;
    /// @dev The maximum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MAX_TICK)
    uint160 private constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

    /// @dev Array of Algebra Factory interfaces used by the contract.
    IAlgebraFactory[] private s_factories;
    /// @dev This mapping holds information about each registered factory.
    mapping(address => AlgebraFactoryData) private s_factoryData;

    constructor(address governor, string memory description) DexAdapter(description) Governable(governor) {}

    /**
     * @dev Registers a new Algebra factory in the system along with its quoter. This function can only be executed by the contract's governor.
     * @param factory The address of the Algebra factory to be registered.
     * @param quoter The address of the quoter associated with this factory.
     * @notice If the factory is already registered, the function will revert with 'AlgebraAdapter__FactoryAlreadyRegistered'.
     *         The factory's data is stored, and the factory is added to the 's_factories' array.
     */
    function addFactory(address factory, address quoter) external onlyGovernor {
        AlgebraFactoryData storage factoryData = s_factoryData[factory];
        if (factoryData.isRegistered) revert AlgebraAdapter__FactoryAlreadyRegistered();
        factoryData.isRegistered = true;
        factoryData.quoter = quoter;
        s_factories.push(IAlgebraFactory(factory));
    }

    /**
     * @dev Removes a factory from the 's_factories' array. This function can only be executed by the contract's governor.
     * @param factoryIndex The index of the factory to be removed.
     * @notice If the factoryIndex is out of bounds, the function will revert with 'AlgebraAdapter__OutOfBound'.
     *         This function deletes the factory's data and removes it from the 's_factories' array.
     * @notice Care must be taken to pass the correct factoryIndex, as an incorrect index can result in the removal of the wrong factory.
     */
    function removeFactory(uint256 factoryIndex) external onlyGovernor {
        uint256 factoriesLen = s_factories.length;
        if (factoriesLen == 0 || factoryIndex >= factoriesLen) revert AlgebraAdapter__OutOfBound();
        delete s_factoryData[address(s_factories[factoryIndex])];
        if (factoryIndex < factoriesLen - 1) {
            s_factories[factoryIndex] = s_factories[factoriesLen - 1];
        }
        s_factories.pop();
    }

    /// @inheritdoc IAlgebraSwapCallback
    function algebraSwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata callbackData)
        external
        override
    {
        if (amount0Delta <= 0 && amount1Delta <= 0) revert AlgebraAdapter__InvalidAmountDeltas();
        SwapCallbackData memory data = abi.decode(callbackData, (SwapCallbackData));
        if (!s_factoryData[data.factory].isRegistered) revert AlgebraAdapter__NotRegisteredFactory();
        if (msg.sender != IAlgebraFactory(data.factory).poolByPair(data.tokenIn, data.tokenOut)) {
            revert AlgebraAdapter__NotAuthorizedPool();
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
        (address factory) = abi.decode(extraArgs, (address));
        if (!s_factoryData[factory].isRegistered) revert AlgebraAdapter__NotRegisteredFactory();
        bool zeroToOne = tokenIn < tokenOut;
        address targetPool = IAlgebraFactory(factory).poolByPair(tokenIn, tokenOut);
        if (targetPool == address(0)) revert AlgebraAdapter__InvalidPool();
        SwapCallbackData memory callbackData =
            SwapCallbackData({sender: msg.sender, tokenIn: tokenIn, tokenOut: tokenOut, factory: factory});
        (int256 amount0Delta, int256 amount1Delta) = IAlgebraPool(targetPool).swap(
            to,
            zeroToOne,
            int256(amountIn),
            zeroToOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1,
            abi.encode(callbackData)
        );
        if (zeroToOne && uint256(-amount1Delta) < amountOut) {
            revert AlgebraAdapter__InsufficentOutput();
        } else if (!zeroToOne && uint256(-amount0Delta) < amountOut) {
            revert AlgebraAdapter__InsufficentOutput();
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
        bool success;
        bytes memory returnData;
        IAlgebraFactory targetFactory;
        bytes memory encodedQuoterParams = abi.encodeWithSelector(IAlgebraQuoter.quoteExactInputSingle.selector, IAlgebraQuoter.QuoteExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            sqrtPriceLimitX96: 0
        }));
        for (uint256 i = 0; i < factoriesLen;) {
            targetFactory = s_factories[i];
            (success, returnData) = s_factoryData[address(targetFactory)].quoter.staticcall(encodedQuoterParams);
            if (success) {
                tempOutput = abi.decode(returnData, (uint256));
                if (tempOutput > maxOutput) {
                    maxOutput = tempOutput;
                    extraArgs = abi.encode(targetFactory);
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
     * @notice The function will return the address of the factory along with its quoter.
     *         It is important to ensure that the factoryIndex is within the bounds of the array to avoid out-of-bounds errors.
     */
    function getFactoryAtIndex(uint256 factoryIndex)
        external
        view
        returns (address factory, address quoter)
    {
        factory = address(s_factories[factoryIndex]);
        AlgebraFactoryData memory factoryData = s_factoryData[factory];
        quoter = factoryData.quoter;
    }

    /// @return factoriesLength The number of factories currently registered
    function allFactoriesLength() external view returns (uint256) {
        return s_factories.length;
    }
}

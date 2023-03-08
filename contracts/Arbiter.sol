//SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AutomationCompatible} from "@chainlink/contracts/src/v0.8/AutomationCompatible.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IUniswapV3PoolActions} from "@uniswap/v3-core/contracts/interfaces/pool/IUniswapV3PoolActions.sol";
import {IArbiter} from "./interfaces/IArbiter.sol";
import {IFlashLiquidityPair} from "./interfaces/IFlashLiquidityPair.sol";
import {IUniswapV3Router} from "./interfaces/IUniswapV3Router.sol";
import {IUniswapV3Quoter} from "./interfaces/IUniswapV3Quoter.sol";
import {IAlgebraRouter} from "./interfaces/IAlgebraRouter.sol";
import {IAlgebraQuoter} from "./interfaces/IAlgebraQuoter.sol";
import {IKyberswapRouter} from "./interfaces/IKyberswapRouter.sol";
import {BastionConnector} from "./types/BastionConnector.sol";
import {FullMath} from "./libraries/FullMath.sol";
import {Babylonian} from "./libraries/Babylonian.sol";

contract Arbiter is IArbiter, BastionConnector, AutomationCompatible {
    using SafeERC20 for IERC20;

    ArbiterJob[] private jobs;
    mapping(address => ArbiterJobConfig) internal jobsConfig;
    mapping(address => AggregatorV3Interface) internal priceFeeds; //USD
    mapping(PoolType => address) internal quoters;
    mapping(address => address) internal routers;
    address private permissionedPairAddress = address(1);
    uint24 private constant FL_FEE = 9994;

    constructor(
        address _governor,
        address _bastion,
        uint256 _transferGovernanceDelay
    ) BastionConnector(_governor, _bastion, _transferGovernanceDelay) {}

    function getJob(uint256 _index) external view returns (ArbiterJob memory) {
        return jobs[_index];
    }

    function getJobConfig(uint256 _index) external view returns (ArbiterJobConfig memory) {
        return jobsConfig[jobs[_index].flPool];
    }

    function setPriceFeeds(
        address[] calldata _tokens,
        address[] calldata _priceFeeds
    ) external onlyGovernor {
        for (uint256 i = 0; i < _tokens.length; ) {
            priceFeeds[_tokens[i]] = AggregatorV3Interface(_priceFeeds[i]);
            unchecked {
                i++;
            }
        }
    }

    function setQuoters(
        PoolType[] calldata _poolTypes,
        address[] calldata _quoters
    ) external onlyGovernor {
        for (uint256 i = 0; i < _poolTypes.length; ) {
            quoters[_poolTypes[i]] = _quoters[i];
            unchecked {
                i++;
            }
        }
    }

    function setRouters(
        address[] calldata _pools,
        address[] calldata _routers
    ) external onlyGovernor {
        for (uint256 i = 0; i < _pools.length; ) {
            routers[_pools[i]] = _routers[i];
            unchecked {
                i++;
            }
        }
    }

    function pushArbiterJob(
        address _farm,
        address _flashPool,
        uint32 _adjFactor,
        uint128 _minProfitInUsd,
        bool _token0IsRewardToken,
        Pool[] calldata _pools
    ) external onlyGovernor {
        IFlashLiquidityPair pair = IFlashLiquidityPair(_flashPool);
        (address _token0, address _token1) = (pair.token0(), pair.token1());
        jobs.push(
            ArbiterJob({
                flFarm: _farm,
                flPool: _flashPool,
                token0: _token0,
                token1: _token1,
                token0IsRewardToken: _token0IsRewardToken
            })
        );
        ArbiterJobConfig storage config = jobsConfig[_flashPool];
        config.token0Decimals = ERC20(_token0).decimals();
        config.token1Decimals = ERC20(_token1).decimals();
        config.adjFactor = _adjFactor;
        config.minProfitInUsd = _minProfitInUsd;
        for (uint256 i = 0; i < _pools.length; ) {
            config.targetPools.push(_pools[i]);
            unchecked {
                i++;
            }
        }
        emit NewJob(_farm, _flashPool);
    }

    function setArbiterJobConfig(
        uint32 _jobIndex,
        uint32 _adjFactor,
        uint128 _minProfitInUsd
    ) external onlyGovernor {
        if (_minProfitInUsd == 0) revert ZeroProfit();
        if (_adjFactor < 10) revert AdjFactorTooLow();
        ArbiterJob memory job = jobs[_jobIndex];
        ArbiterJobConfig storage config = jobsConfig[job.flPool];
        config.adjFactor = _adjFactor;
        config.minProfitInUsd = _minProfitInUsd;
        emit JobParamsChanged(_jobIndex, _adjFactor, _minProfitInUsd);
    }

    function removeArbiterJob(uint256 jobIndex) external onlyGovernor {
        uint256 jobLastIndex = jobs.length - 1;
        if (jobIndex < jobLastIndex) {
            jobs[jobIndex] = jobs[jobLastIndex];
        }
        jobs.pop();
        emit JobRemoved(jobIndex);
    }

    function pushPoolToJob(
        uint256 jobIndex,
        address _pool,
        PoolType _type,
        uint24 _fee
    ) external onlyGovernor {
        Pool storage pool = jobsConfig[jobs[jobIndex].flPool].targetPools.push();
        pool.poolAddr = _pool;
        pool.poolType = _type;
        pool.poolFee = _fee;
        emit PoolAddedToJob(jobIndex, _pool, _type, _fee);
    }

    function removePoolFromJob(uint256 jobIndex, uint8 poolIndex) external onlyGovernor {
        ArbiterJob memory _job = jobs[jobIndex];
        ArbiterJobConfig storage _config = jobsConfig[_job.flPool];
        uint256 poolsLastIndex = _config.targetPools.length - 1;
        if (poolIndex < poolsLastIndex) {
            _config.targetPools[poolIndex] = _config.targetPools[poolsLastIndex];
        }
        emit PoolRemovedFromJob(jobIndex, poolIndex);
    }

    function computeProfitMaximizingTrade(
        address _flashPool,
        address _token0,
        address _token1,
        uint8 _token0Decimals,
        uint8 _token1Decimals
    ) internal view returns (bool zeroToOne, uint256 amountIn, uint256 amountOut) {
        (uint256 reserve0, uint256 reserve1, ) = IFlashLiquidityPair(_flashPool).getReserves();
        (uint256 price0, uint256 price1) = getTrueRates(
            _token0,
            _token1,
            _token0Decimals,
            _token1Decimals
        );
        zeroToOne = FullMath.mulDiv(reserve0, price1, reserve1) < price0;
        uint256 invariant = reserve0 * reserve1;
        uint256 leftSide = Babylonian.sqrt(
            FullMath.mulDiv(
                invariant * 10000,
                zeroToOne ? price0 : price1,
                (zeroToOne ? price1 : price0) * FL_FEE
            )
        );
        uint256 rightSide = (zeroToOne ? reserve0 * 10000 : reserve1 * 10000) / FL_FEE;
        if (leftSide < rightSide) return (false, 0, 0);
        amountIn = uint112(leftSide - rightSide);
        (reserve0, reserve1) = zeroToOne ? (reserve0, reserve1) : (reserve1, reserve0);
        amountOut = uint112(getAmountOutUniswapV2(amountIn, reserve0, reserve1, FL_FEE));
    }

    function getTrueRates(
        address _token0,
        address _token1,
        uint8 _token0Decimals,
        uint8 _token1Decimals
    ) internal view returns (uint256, uint256) {
        int256 token0Decimals = int256(10 ** uint256(_token0Decimals));
        int256 token1Decimals = int256(10 ** uint256(_token1Decimals));
        (, int256 price0, , , ) = priceFeeds[_token0].latestRoundData();
        (, int256 price1, , , ) = priceFeeds[_token1].latestRoundData();
        return (uint256(token0Decimals), uint256((price0 * token1Decimals) / price1));
    }

    function getAmountInUniswapV2(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut,
        uint24 poolFee
    ) internal pure returns (uint256 amountIn) {
        if (amountOut == 0) revert InsufficentInput();
        if (reserveIn == 0 || reserveOut == 0) revert InsufficentLiquidity();
        uint256 numerator = reserveIn * amountOut * 10000;
        uint256 denominator = reserveOut - amountOut * poolFee;
        amountIn = (numerator / denominator) + 1;
    }

    function getAmountOutUniswapV2(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut,
        uint24 poolFee
    ) internal pure returns (uint256 amountOut) {
        if (amountIn == 0) revert InsufficentInput();
        if (reserveIn == 0 || reserveOut == 0) revert InsufficentLiquidity();
        uint256 amountInWithFee = amountIn * poolFee;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 10000) + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function getAmountOut(
        uint256 amountIn,
        bool zeroToOne,
        address token0,
        address token1,
        Pool memory pool
    ) internal view returns (uint256 amountOut) {
        (address tokenIn, address tokenOut) = zeroToOne ? (token0, token1) : (token1, token0);
        if (pool.poolType == PoolType.UniswapV2) {
            (uint256 reserve0, uint256 reserve1, ) = IFlashLiquidityPair(pool.poolAddr)
                .getReserves();
            (reserve0, reserve1) = zeroToOne ? (reserve0, reserve1) : (reserve1, reserve0);
            amountOut = getAmountOutUniswapV2(amountIn, reserve0, reserve1, pool.poolFee);
        } else if (pool.poolType == PoolType.UniswapV3 || pool.poolType == PoolType.KyberSwap) {
            IUniswapV3Quoter.QuoteExactInputSingleParams memory params = IUniswapV3Quoter
                .QuoteExactInputSingleParams(tokenIn, tokenOut, amountIn, pool.poolFee, 0);
            amountOut = IUniswapV3Quoter(quoters[pool.poolType]).quoteExactInputSingle(params);
        } else if (pool.poolType == PoolType.Algebra) {
            IAlgebraQuoter.QuoteExactInputSingleParams memory params = IAlgebraQuoter
                .QuoteExactInputSingleParams(tokenIn, tokenOut, amountIn, 0);
            amountOut = IAlgebraQuoter(quoters[pool.poolType]).quoteExactInputSingle(params);
        }
    }

    function withdraw(address _farm, uint256 _balance, IERC20 _token) internal {
        //uint256 _balance = _token.balanceOf(address(this));
        if (_balance > 0) {
            uint256 fee = _balance / 50; // 2%
            _balance = _balance - fee;
            _token.safeTransfer(_farm, _balance);
            _token.safeTransfer(bastion, fee);
            emit ProfitsDistributed(_farm, address(_token), _balance);
        }
    }

    function getUsdValue(address token, uint256 amount) internal view returns (uint256 usdValue) {
        uint8 _tokenDecimals = ERC20(token).decimals();
        uint256 tokenDecimals = 10 ** uint256(_tokenDecimals);
        (, int256 price, , , ) = priceFeeds[token].latestRoundData();
        uint256 temp = uint256(price) * amount;
        if (temp > tokenDecimals) usdValue = temp / tokenDecimals;
    }

    function flashLiquidityCall(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes memory data
    ) public {
        if (msg.sender != permissionedPairAddress) revert NotPermissioned();
        if (sender != address(this)) revert NotAuthorized();
        CallbackData memory info = abi.decode(data, (CallbackData));
        (address tokenIn, address tokenOut) = info.zeroToOne
            ? (info.token0, info.token1)
            : (info.token1, info.token0);
        if (info.targetPool.poolType == PoolType.UniswapV2) {
            (uint128 amount0Out, uint128 amount1Out) = info.zeroToOne
                ? (uint128(0), info.amountOutExt)
                : (info.amountOutExt, uint128(0));
            IERC20(tokenIn).safeTransfer(info.targetPool.poolAddr, amount0 > 0 ? amount0 : amount1);
            IFlashLiquidityPair(info.targetPool.poolAddr).swap(
                amount0Out,
                amount1Out,
                address(this),
                new bytes(0)
            );
        } else if (info.targetPool.poolType == PoolType.UniswapV3) {
            address _router = routers[info.targetPool.poolAddr];
            IERC20(tokenIn).approve(_router, amount0 > 0 ? amount0 : amount1);
            IUniswapV3Router.ExactInputSingleParams memory params = IUniswapV3Router
                .ExactInputSingleParams(
                    tokenIn,
                    tokenOut,
                    info.targetPool.poolFee,
                    address(this),
                    block.timestamp,
                    amount0 > 0 ? amount0 : amount1,
                    info.amountOutExt,
                    0
                );
            IUniswapV3Router(_router).exactInputSingle(params);
        } else if (info.targetPool.poolType == PoolType.Algebra) {
            address _router = routers[info.targetPool.poolAddr];
            IERC20(tokenIn).approve(_router, amount0 > 0 ? amount0 : amount1);
            IAlgebraRouter.ExactInputSingleParams memory params = IAlgebraRouter
                .ExactInputSingleParams(
                    tokenIn,
                    tokenOut,
                    address(this),
                    block.timestamp,
                    amount0 > 0 ? amount0 : amount1,
                    info.amountOutExt,
                    0
                );
            IAlgebraRouter(_router).exactInputSingle(params);
        } else if (info.targetPool.poolType == PoolType.KyberSwap) {
            address _router = routers[info.targetPool.poolAddr];
            IERC20(tokenIn).approve(_router, amount0 > 0 ? amount0 : amount1);
            IKyberswapRouter.ExactInputSingleParams memory params = IKyberswapRouter
                .ExactInputSingleParams(
                    tokenIn,
                    tokenOut,
                    info.targetPool.poolFee,
                    address(this),
                    block.timestamp,
                    amount0 > 0 ? amount0 : amount1,
                    info.amountOutExt,
                    0
                );
            IKyberswapRouter(_router).swapExactInputSingle(params);
        } else {
            revert UnknownPoolType();
        }
        IERC20(tokenOut).safeTransfer(info.flPool, info.amountDebt);
    }

    function checkUpkeep(
        bytes calldata checkData
    ) external view override returns (bool upkeepNeeded, bytes memory performData) {
        uint256 jobIndex = abi.decode(checkData, (uint256));
        ArbiterJob memory job = jobs[jobIndex];
        ArbiterJobConfig memory config = jobsConfig[job.flPool];
        (
            bool zeroToOne,
            uint256 amountInFlash,
            uint256 amountOutFlash
        ) = computeProfitMaximizingTrade(
                job.flPool,
                job.token0,
                job.token1,
                config.token0Decimals,
                config.token1Decimals
            );
        if (amountInFlash == 0) return (false, new bytes(0));
        uint32 bestPoolIndex;
        uint256 bestProfit;
        uint256 tempProfit;
        uint256 amountOutExt;
        uint256 amountOutExtTemp;
        for (uint32 i = 0; i < config.targetPools.length; ) {
            amountOutExtTemp = getAmountOut(
                amountOutFlash,
                !zeroToOne,
                job.token0,
                job.token1,
                config.targetPools[i]
            );
            tempProfit = amountOutExtTemp > amountInFlash ? amountOutExtTemp - amountInFlash : 0;
            if (tempProfit > bestProfit) {
                bestPoolIndex = i;
                bestProfit = tempProfit;
                amountOutExt = amountOutExtTemp;
            }
            unchecked {
                i++;
            }
        }
        bestProfit -= bestProfit / config.adjFactor;
        if (getUsdValue(zeroToOne ? job.token0 : job.token1, bestProfit) > config.minProfitInUsd) {
            ArbiterCall memory arbiterCall = ArbiterCall(
                uint32(jobIndex),
                bestPoolIndex,
                uint112(bestProfit),
                uint112(amountInFlash),
                uint112(amountOutFlash),
                uint112(amountOutExt),
                job.token0IsRewardToken == zeroToOne,
                zeroToOne
            );
            upkeepNeeded = true;
            performData = abi.encode(arbiterCall);
        }
    }

    function performUpkeep(bytes calldata performData) external override {
        ArbiterCall memory call = abi.decode(performData, (ArbiterCall));
        ArbiterJob memory job = jobs[call.jobIndex];
        CallbackData memory callbackData = CallbackData(
            job.flPool,
            jobsConfig[job.flPool].targetPools[call.bestPoolIndex],
            job.token0,
            job.token1,
            call.amountInFlash,
            call.amountOutExt,
            !call.zeroToOne
        );
        bytes memory data = abi.encode(callbackData);
        permissionedPairAddress = job.flPool;
        (IERC20 baseToken, IERC20 quoteToken) = job.token0IsRewardToken
            ? (IERC20(job.token0), IERC20(job.token1))
            : (IERC20(job.token1), IERC20(job.token0));
        (uint112 amount0Flash, uint112 amount1Flash) = call.zeroToOne
            ? (uint112(0), call.amountOutFlash)
            : (call.amountOutFlash, uint112(0));
        uint256 balanceBefore = baseToken.balanceOf(address(this));
        IFlashLiquidityPair _flPool = IFlashLiquidityPair(job.flPool);
        _flPool.swap(amount0Flash, amount1Flash, address(this), data);
        if (!call.tokenInIsRewardToken) {
            uint256 balance = quoteToken.balanceOf(address(this));
            (uint256 reserve0, uint256 reserve1, ) = _flPool.getReserves();
            (reserve0, reserve1) = call.zeroToOne ? (reserve0, reserve1) : (reserve1, reserve0);
            uint256 _amountOut = getAmountOutUniswapV2(balance, reserve0, reserve1, FL_FEE);
            (uint256 amount0Out, uint256 amount1Out) = call.zeroToOne
                ? (uint256(0), _amountOut)
                : (_amountOut, uint256(0));
            quoteToken.safeTransfer(job.flPool, balance);
            _flPool.swap(amount0Out, amount1Out, address(this), new bytes(0));
        }
        uint256 _profit = baseToken.balanceOf(address(this)) - balanceBefore;
        if (_profit < call.bestProfit) revert NotProfitable();
        permissionedPairAddress = address(1);
        withdraw(job.flFarm, _profit, baseToken);
    }
}

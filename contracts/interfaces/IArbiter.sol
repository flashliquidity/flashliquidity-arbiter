// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IArbiter {
    struct ArbiterJob {
        address flFarm;
        address flPool;
        address token0;
        address token1;
        bool token0IsRewardToken;
    }
    struct ArbiterJobConfig {
        uint8 token0Decimals;
        uint8 token1Decimals;
        uint32 adjFactor;
        uint128 minProfitInUsd;
        Pool[] targetPools;
    }
    struct ArbiterCall {
        uint32 jobIndex;
        uint32 bestPoolIndex;
        uint112 bestProfit;
        uint112 amountInFlash;
        uint112 amountOutFlash;
        uint112 amountOutExt;
        bool tokenInIsRewardToken;
        bool zeroToOne;
    }
    struct CallbackData {
        address flPool;
        Pool targetPool;
        address token0;
        address token1;
        uint128 amountDebt;
        uint128 amountOutExt;
        bool zeroToOne;
    }
    enum PoolType {
        UniswapV2,
        UniswapV3,
        Algebra,
        KyberSwap
    }
    struct Pool {
        address poolAddr;
        PoolType poolType;
        uint24 poolFee;
    }

    error OutOfBound();
    error ZeroProfit();
    error AdjFactorTooLow();
    error UnknownPoolType();
    error InsufficentInput();
    error InsufficentLiquidity();
    error NotPermissioned();
    error NotProfitable();

    event ProfitsDistributed(
        address indexed _farm,
        address indexed _rewardToken,
        uint256 indexed _amount
    );
    event NewJob(address indexed _farm, address indexed _flPool);
    event JobParamsChanged(
        uint32 indexed _jobIndex,
        uint32 indexed _adjFactor,
        uint128 indexed _minProfitInUsd
    );
    event JobRemoved(uint256 indexed _jobIndex);
    event PoolAddedToJob(
        uint256 indexed jobIndex,
        address indexed poolAddr,
        PoolType indexed poolType,
        uint24 poolFee
    );
    event PoolRemovedFromJob(uint256 indexed jobIndex, uint256 indexed indexPool);

    function getJob(uint256 _index) external view returns (ArbiterJob calldata);

    function setPriceFeeds(address[] calldata _tokens, address[] calldata _priceFeeds) external;

    function setQuoters(PoolType[] calldata _poolTypes, address[] calldata _quoters) external;

    function setRouters(address[] calldata _pools, address[] calldata _routers) external;

    function pushArbiterJob(
        address _farm,
        address _flashPool,
        uint32 adjFactor,
        uint128 _minProfitInUsd,
        bool token0IsRewardToken,
        Pool[] calldata targetPools
    ) external;

    function removeArbiterJob(uint256 jobIndex) external;

    function pushPoolToJob(uint256 jobIndex, address _pool, PoolType _type, uint24 _fee) external;

    function setArbiterJobConfig(
        uint32 _jobIndex,
        uint32 _adjFactor,
        uint128 _minProfitInUsd
    ) external;

    function removePoolFromJob(uint256 jobIndex, uint8 poolIndex) external;

    function flashLiquidityCall(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes memory data
    ) external;
}

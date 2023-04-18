// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IArbiter {
    function maxStaleness() external view returns (uint256);

    function getJob(
        uint256 _index
    )
        external
        view
        returns (
            address flFarm,
            address flPool,
            address token0,
            address token1,
            bool token0IsRewardToken
        );

    function getJobConfig(
        uint256 _index
    )
        external
        view
        returns (
            uint8 token0Decimals,
            uint8 token1Decimals,
            uint32 adjFactor,
            uint32 reserveToProfitRatio,
            address[] memory targetPools,
            uint256[] memory poolTypes,
            uint24[] memory poolFees
        );

    function setPriceFeeds(address[] calldata _tokens, address[] calldata _priceFeeds) external;

    function setQuoters(address[] calldata _poolTypes, address[] calldata _quoters) external;

    function setRouters(address[] calldata _pools, address[] calldata _routers) external;

    function pushArbiterJob(
        address _farm,
        address _flashPool,
        uint32 _adjFactor,
        uint32 _reserveToProfitRatio,
        bool _token0IsRewardToken,
        address[] calldata _targetPools,
        uint256[] calldata _poolTypes,
        uint24[] calldata _poolFees
    ) external;

    function removeArbiterJob(uint256 jobIndex) external;

    function pushPoolToJob(uint256 jobIndex, address _pool, uint256 _type, uint24 _fee) external;

    function setArbiterJobConfig(
        uint32 _jobIndex,
        uint32 _adjFactor,
        uint32 _reserveToProfitRatio
    ) external;

    function removePoolFromJob(uint256 _jobIndex, uint8 _poolIndex) external;

    function flashLiquidityCall(
        address _sender,
        uint256 _amount0,
        uint256 _amount1,
        bytes memory _data
    ) external;
}

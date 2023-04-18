import { ethers, network } from "hardhat"
import { expect } from "chai"
import { setStorageAt, time } from "@nomicfoundation/hardhat-network-helpers"
import { ADDRESS_ZERO, FACTORY_ADDR, ROUTER_ADDR } from "./utilities"

describe("Arbiter", function () {
    before(async function () {
        this.signers = await ethers.getSigners()
        this.governor = this.signers[0]
        this.transferGovernanceDelay = 60
        this.bob = this.signers[1]
        this.dev = this.signers[2]
        this.minter = this.signers[3]
        this.alice = this.signers[4]
        this.farm = this.signers[5]
        this.lpToken = this.signers[6]
        this.adjFactor = 100
        this.reserveToProfitRatio = 10000
        this.maxStaleness = 180
        this.maticUsdcPair = "0x0C9580eC848bd48EBfCB85A4aE1f0354377315fD"
        this.Arbiter = await ethers.getContractFactory("Arbiter")
        this.ERC20 = await ethers.getContractFactory("ERC20")
        this.router = await ethers.getContractAt("IFlashLiquidityRouter", ROUTER_ADDR)
        this.factory = await ethers.getContractAt("IFlashLiquidityFactory", FACTORY_ADDR)
        this.extRouter = await ethers.getContractAt(
            "IFlashLiquidityRouter",
            "0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff"
        )
    })

    beforeEach(async function () {
        await network.provider.request({
            method: "hardhat_reset",
            params: [
                {
                    forking: {
                        enabled: true,
                        jsonRpcUrl: process.env.ALCHEMY_MAINNET_RPC_URL,
                        blockNumber: 41400000,
                    },
                },
            ],
        })
        this.arbiter = await this.Arbiter.deploy(
            this.governor.address,
            this.governor.address,
            this.transferGovernanceDelay,
            this.maxStaleness
        )
        await this.arbiter.deployed()
        await this.arbiter.setPriceFeeds(
            [
                "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270",
                "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174",
            ],
            [
                "0xAB594600376Ec9fD91F8e885dADF0CE036862dE0",
                "0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7",
            ]
        )
        await this.arbiter.setQuoters(
            [
                "0xA374094527e1673A86dE625aa59517c5dE346d32",
                "0xAE81FAc689A1b4b1e06e7ef4a2ab4CD8aC0A087D",
                "0x50FEEdF7fB2F511112287091819F21eb0F3Ce498",
            ],
            [
                "0x7637Aaeb5BD58269B782726680d83f72C651aE74",
                "0x2E0A046481c676235B806Bd004C4b492C850fb34",
                "0x6524fDB494679a12B2f1d1B051D8dEedB2E5cc25",
            ]
        )
        await this.arbiter.setRouters(
            [
                "0xA374094527e1673A86dE625aa59517c5dE346d32",
                "0xAE81FAc689A1b4b1e06e7ef4a2ab4CD8aC0A087D",
                "0x50FEEdF7fB2F511112287091819F21eb0F3Ce498",
            ],
            [
                "0xe592427a0aece92de3edee1f18e0157c05861564",
                "0xf5b509bB0909a69B1c207E495f687a596C168E12",
                "0xC1e7dFE73E1598E3910EF4C7845B68A9Ab6F4c83",
            ]
        )
        this.usdc = this.ERC20.attach("0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174")
        await setStorageAt(
            this.factory.address,
            2,
            ethers.utils.hexlify(ethers.utils.zeroPad(this.governor.address, 32))
        )
        await this.factory.connect(this.governor).setPairManager(this.maticUsdcPair, ADDRESS_ZERO)
    })

    it("Should not allow to set pendingGovernor to zero address", async function () {
        await expect(
            this.arbiter.connect(this.governor).setPendingGovernor(ADDRESS_ZERO)
        ).to.be.revertedWith("ZeroAddress()")
    })

    it("Should allow to transfer governance only after min delay has passed from request", async function () {
        await this.arbiter.connect(this.governor).setPendingGovernor(this.bob.address)
        await expect(this.arbiter.transferGovernance()).to.be.revertedWith("TooEarly()")
        await time.increase(this.transferGovernanceDelay)
        await this.arbiter.transferGovernance()
        expect(await this.arbiter.governor()).to.be.equal(this.bob.address)
    })

    it("Should allow only Governor to set price feeds", async function () {
        await expect(
            this.arbiter.connect(this.bob).setPriceFeeds([this.bob.address], [this.bob.address])
        ).to.be.revertedWith("NotAuthorized()")
        await this.arbiter
            .connect(this.governor)
            .setPriceFeeds([this.bob.address], [this.bob.address])
    })

    it("Should allow only Governor to set quoters", async function () {
        await expect(
            this.arbiter.connect(this.bob).setQuoters([this.alice.address], [this.bob.address])
        ).to.be.revertedWith("NotAuthorized()")
        await this.arbiter
            .connect(this.governor)
            .setQuoters([this.alice.address], [this.bob.address])
    })

    it("Should allow only Governor to set max staleness", async function () {
        await expect(this.arbiter.connect(this.bob).setMaxStaleness(120)).to.be.revertedWith(
            "NotAuthorized()"
        )
        await this.arbiter.connect(this.governor).setMaxStaleness(120)
    })

    it("Should allow only Governor to set token decimals on job config", async function () {
        await expect(
            this.arbiter.connect(this.bob).setConfigTokensDecimals(this.maticUsdcPair, 8, 8)
        ).to.be.revertedWith("NotAuthorized()")
        await this.arbiter.connect(this.governor).setConfigTokensDecimals(this.maticUsdcPair, 8, 8)
    })

    it("Should allow only Governor to push new jobs", async function () {
        await this.factory
            .connect(this.governor)
            .setPairManager(this.maticUsdcPair, this.arbiter.address)
        await expect(
            this.arbiter
                .connect(this.bob)
                .pushArbiterJob(
                    this.bob.address,
                    this.maticUsdcPair,
                    this.adjFactor,
                    this.reserveToProfitRatio,
                    true,
                    [],
                    [],
                    []
                )
        ).to.be.revertedWith("NotAuthorized()")
        await this.arbiter
            .connect(this.governor)
            .pushArbiterJob(
                this.bob.address,
                this.maticUsdcPair,
                this.adjFactor,
                this.reserveToProfitRatio,
                true,
                [],
                [],
                []
            )
    })

    it("Should allow only Governor to remove jobs", async function () {
        await this.factory
            .connect(this.governor)
            .setPairManager(this.maticUsdcPair, this.arbiter.address)
        await this.arbiter
            .connect(this.governor)
            .pushArbiterJob(
                this.bob.address,
                this.maticUsdcPair,
                this.adjFactor,
                this.reserveToProfitRatio,
                true,
                [],
                [],
                []
            )
        await this.arbiter
            .connect(this.governor)
            .pushArbiterJob(
                this.alice.address,
                this.maticUsdcPair,
                this.adjFactor,
                this.reserveToProfitRatio,
                true,
                [],
                [],
                []
            )
        await expect(this.arbiter.connect(this.bob).removeArbiterJob(0)).to.be.revertedWith(
            "NotAuthorized()"
        )
        await this.arbiter.connect(this.governor).removeArbiterJob(0)
        await this.arbiter.connect(this.governor).removeArbiterJob(0)
    })

    it("Should allow only Governor to push new pools to job", async function () {
        await this.factory
            .connect(this.governor)
            .setPairManager(this.maticUsdcPair, this.arbiter.address)
        await this.arbiter
            .connect(this.governor)
            .pushArbiterJob(
                this.bob.address,
                this.maticUsdcPair,
                this.adjFactor,
                this.reserveToProfitRatio,
                true,
                [],
                [],
                []
            )
        await expect(
            this.arbiter
                .connect(this.bob)
                .pushPoolToJob(0, "0xA374094527e1673A86dE625aa59517c5dE346d32", 1, 500)
        ).to.be.revertedWith("NotAuthorized()")
        await this.arbiter
            .connect(this.governor)
            .pushPoolToJob(0, "0xA374094527e1673A86dE625aa59517c5dE346d32", 1, 500)
        await expect(this.arbiter.connect(this.bob).removePoolFromJob(0, 0)).to.be.revertedWith(
            "NotAuthorized()"
        )
        await this.arbiter.connect(this.governor).removePoolFromJob(0, 0)
    })

    it("SIMULATION: token0 IN, token1 OUT, target: UNI-V2", async function () {
        const jobId = ethers.utils.defaultAbiCoder.encode(["uint256"], ["0"])
        await this.router
            .connect(this.governor)
            .swapExactETHForTokens(
                0,
                [
                    "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270",
                    "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174",
                ],
                this.governor.address,
                2000000000,
                { value: ethers.utils.parseEther("30") }
            )
        await this.factory
            .connect(this.governor)
            .setPairManager(this.maticUsdcPair, this.arbiter.address)
        await this.arbiter.pushArbiterJob(
            this.governor.address,
            this.maticUsdcPair,
            this.adjFactor,
            this.reserveToProfitRatio,
            true,
            ["0x6e7a5FAFcec6BB1e78bAE2A1F0B612012BF14827"],
            [0],
            [9970]
        )
        const ret = await this.arbiter.checkUpkeep(jobId)
        expect(ret.upkeepNeeded).to.be.true
        await this.arbiter.performUpkeep(ret.performData)
    })

    it("SIMULATION: token1 IN, token0 OUT, target: UNI-V2", async function () {
        const jobId = ethers.utils.defaultAbiCoder.encode(["uint256"], ["0"])
        await this.extRouter
            .connect(this.governor)
            .swapExactETHForTokens(
                0,
                [
                    "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270",
                    "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174",
                ],
                this.governor.address,
                2000000000,
                { value: ethers.utils.parseEther("30") }
            )
        const balance = this.usdc.balanceOf(this.governor.address)
        this.usdc.connect(this.governor).approve(this.router.address, balance)
        await this.router
            .connect(this.governor)
            .swapExactTokensForTokens(
                balance,
                0,
                [
                    "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174",
                    "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270",
                ],
                this.governor.address,
                2000000000
            )
        await this.factory
            .connect(this.governor)
            .setPairManager(this.maticUsdcPair, this.arbiter.address)
        await this.arbiter.pushArbiterJob(
            this.governor.address,
            this.maticUsdcPair,
            this.adjFactor,
            this.reserveToProfitRatio,
            true,
            ["0x6e7a5FAFcec6BB1e78bAE2A1F0B612012BF14827"],
            [0],
            [9970]
        )
        const ret = await this.arbiter.checkUpkeep(jobId)
        expect(ret.upkeepNeeded).to.be.true
        await this.arbiter.performUpkeep(ret.performData)
    })

    it("SIMULATION: token0 IN, token1 OUT, target: UNI-V3", async function () {
        const jobId = ethers.utils.defaultAbiCoder.encode(["uint256"], ["0"])
        await this.router
            .connect(this.governor)
            .swapExactETHForTokens(
                0,
                [
                    "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270",
                    "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174",
                ],
                this.governor.address,
                2000000000,
                { value: ethers.utils.parseEther("30") }
            )
        await this.factory
            .connect(this.governor)
            .setPairManager(this.maticUsdcPair, this.arbiter.address)
        await this.arbiter.pushArbiterJob(
            this.governor.address,
            this.maticUsdcPair,
            this.adjFactor,
            this.reserveToProfitRatio,
            true,
            ["0xA374094527e1673A86dE625aa59517c5dE346d32"],
            [1],
            [500]
        )
        const ret = await this.arbiter.checkUpkeep(jobId)
        expect(ret.upkeepNeeded).to.be.true
        await this.arbiter.performUpkeep(ret.performData)
    })

    it("SIMULATION: token1 IN, token0 OUT, target: UNI-V3", async function () {
        const jobId = ethers.utils.defaultAbiCoder.encode(["uint256"], ["0"])
        await this.extRouter
            .connect(this.governor)
            .swapExactETHForTokens(
                0,
                [
                    "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270",
                    "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174",
                ],
                this.governor.address,
                2000000000,
                { value: ethers.utils.parseEther("30") }
            )
        this.usdc = this.ERC20.attach("0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174")
        const balance = this.usdc.balanceOf(this.governor.address)
        this.usdc.connect(this.governor).approve(this.router.address, balance)
        await this.router
            .connect(this.governor)
            .swapExactTokensForTokens(
                balance,
                0,
                [
                    "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174",
                    "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270",
                ],
                this.governor.address,
                2000000000
            )
        await this.factory
            .connect(this.governor)
            .setPairManager(this.maticUsdcPair, this.arbiter.address)
        await this.arbiter.pushArbiterJob(
            this.governor.address,
            this.maticUsdcPair,
            this.adjFactor,
            this.reserveToProfitRatio,
            true,
            ["0xA374094527e1673A86dE625aa59517c5dE346d32"],
            [1],
            [500]
        )
        const ret = await this.arbiter.checkUpkeep(jobId)
        expect(ret.upkeepNeeded).to.be.true
        await this.arbiter.performUpkeep(ret.performData)
    })

    it("SIMULATION: token0 IN, token1 OUT, target: Algebra", async function () {
        const jobId = ethers.utils.defaultAbiCoder.encode(["uint256"], ["0"])
        await this.router
            .connect(this.governor)
            .swapExactETHForTokens(
                0,
                [
                    "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270",
                    "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174",
                ],
                this.governor.address,
                2000000000,
                { value: ethers.utils.parseEther("30") }
            )
        await this.factory
            .connect(this.governor)
            .setPairManager(this.maticUsdcPair, this.arbiter.address)
        await this.arbiter.pushArbiterJob(
            this.governor.address,
            this.maticUsdcPair,
            this.adjFactor,
            this.reserveToProfitRatio,
            true,
            ["0xAE81FAc689A1b4b1e06e7ef4a2ab4CD8aC0A087D"],
            [2],
            [350]
        )
        const ret = await this.arbiter.checkUpkeep(jobId)
        expect(ret.upkeepNeeded).to.be.true
        await this.arbiter.performUpkeep(ret.performData)
    })

    it("SIMULATION: token1 IN, token0 OUT, target: Algebra", async function () {
        const jobId = ethers.utils.defaultAbiCoder.encode(["uint256"], ["0"])
        await this.extRouter
            .connect(this.governor)
            .swapExactETHForTokens(
                0,
                [
                    "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270",
                    "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174",
                ],
                this.governor.address,
                2000000000,
                { value: ethers.utils.parseEther("30") }
            )
        const balance = this.usdc.balanceOf(this.governor.address)
        this.usdc.connect(this.governor).approve(this.router.address, balance)
        await this.router
            .connect(this.governor)
            .swapExactTokensForTokens(
                balance,
                0,
                [
                    "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174",
                    "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270",
                ],
                this.governor.address,
                2000000000
            )
        await this.factory
            .connect(this.governor)
            .setPairManager(this.maticUsdcPair, this.arbiter.address)
        await this.arbiter.pushArbiterJob(
            this.governor.address,
            this.maticUsdcPair,
            this.adjFactor,
            this.reserveToProfitRatio,
            true,
            ["0xAE81FAc689A1b4b1e06e7ef4a2ab4CD8aC0A087D"],
            [2],
            [350]
        )
        const ret = await this.arbiter.checkUpkeep(jobId)
        expect(ret.upkeepNeeded).to.be.true
        await this.arbiter.performUpkeep(ret.performData)
    })

    it("SIMULATION: token0 IN, token1 OUT, target: Kyberswap", async function () {
        const jobId = ethers.utils.defaultAbiCoder.encode(["uint256"], ["0"])
        await this.router
            .connect(this.governor)
            .swapExactETHForTokens(
                0,
                [
                    "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270",
                    "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174",
                ],
                this.governor.address,
                2000000000,
                { value: ethers.utils.parseEther("30") }
            )
        await this.factory
            .connect(this.governor)
            .setPairManager(this.maticUsdcPair, this.arbiter.address)
        await this.arbiter.pushArbiterJob(
            this.governor.address,
            this.maticUsdcPair,
            this.adjFactor,
            this.reserveToProfitRatio,
            true,
            ["0x50FEEdF7fB2F511112287091819F21eb0F3Ce498"],
            [3],
            [1000]
        )
        const ret = await this.arbiter.checkUpkeep(jobId)
        expect(ret.upkeepNeeded).to.be.true
        await this.arbiter.performUpkeep(ret.performData)
    })

    it("SIMULATION: token1 IN, token0 OUT, target: Kyberswap", async function () {
        const jobId = ethers.utils.defaultAbiCoder.encode(["uint256"], ["0"])
        await this.extRouter
            .connect(this.governor)
            .swapExactETHForTokens(
                0,
                [
                    "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270",
                    "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174",
                ],
                this.governor.address,
                2000000000,
                { value: ethers.utils.parseEther("30") }
            )
        const balance = this.usdc.balanceOf(this.governor.address)
        this.usdc.connect(this.governor).approve(this.router.address, balance)
        await this.router
            .connect(this.governor)
            .swapExactTokensForTokens(
                balance,
                0,
                [
                    "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174",
                    "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270",
                ],
                this.governor.address,
                2000000000
            )
        await this.factory
            .connect(this.governor)
            .setPairManager(this.maticUsdcPair, this.arbiter.address)
        await this.arbiter.pushArbiterJob(
            this.governor.address,
            this.maticUsdcPair,
            this.adjFactor,
            this.reserveToProfitRatio,
            true,
            ["0x50FEEdF7fB2F511112287091819F21eb0F3Ce498"],
            [3],
            [1000]
        )
        const ret = await this.arbiter.checkUpkeep(jobId)
        expect(ret.upkeepNeeded).to.be.true
        await this.arbiter.performUpkeep(ret.performData)
    })

    it("SIMULATION: Full rebalancing scenario: token0 IN, token1 OUT", async function () {
        const jobId = ethers.utils.defaultAbiCoder.encode(["uint256"], ["0"])
        await this.router
            .connect(this.governor)
            .swapExactETHForTokens(
                0,
                [
                    "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270",
                    "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174",
                ],
                this.governor.address,
                2000000000,
                { value: ethers.utils.parseEther("30") }
            )
        await this.factory
            .connect(this.governor)
            .setPairManager(this.maticUsdcPair, this.arbiter.address)
        await this.arbiter.pushArbiterJob(
            this.governor.address,
            this.maticUsdcPair,
            this.adjFactor,
            this.reserveToProfitRatio,
            true,
            [
                "0x6e7a5FAFcec6BB1e78bAE2A1F0B612012BF14827",
                "0xA374094527e1673A86dE625aa59517c5dE346d32",
                "0xAE81FAc689A1b4b1e06e7ef4a2ab4CD8aC0A087D",
                "0x50FEEdF7fB2F511112287091819F21eb0F3Ce498",
            ],
            [0, 1, 2, 3],
            [9970, 500, 350, 1000]
        )
        const ret = await this.arbiter.checkUpkeep(jobId)
        expect(ret.upkeepNeeded).to.be.true
        await this.arbiter.performUpkeep(ret.performData)
    })

    it("SIMULATION: Full rebalancing scenario: token1 IN, token0 OUT", async function () {
        const jobId = ethers.utils.defaultAbiCoder.encode(["uint256"], ["0"])
        await this.extRouter
            .connect(this.governor)
            .swapExactETHForTokens(
                0,
                [
                    "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270",
                    "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174",
                ],
                this.governor.address,
                2000000000,
                { value: ethers.utils.parseEther("30") }
            )
        const balance = this.usdc.balanceOf(this.governor.address)
        this.usdc.connect(this.governor).approve(this.router.address, balance)
        await this.router
            .connect(this.governor)
            .swapExactTokensForTokens(
                balance,
                0,
                [
                    "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174",
                    "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270",
                ],
                this.governor.address,
                2000000000
            )
        await this.factory
            .connect(this.governor)
            .setPairManager(this.maticUsdcPair, this.arbiter.address)
        await this.arbiter.pushArbiterJob(
            this.governor.address,
            this.maticUsdcPair,
            this.adjFactor,
            this.reserveToProfitRatio,
            true,
            [
                "0x6e7a5FAFcec6BB1e78bAE2A1F0B612012BF14827",
                "0xA374094527e1673A86dE625aa59517c5dE346d32",
                "0xAE81FAc689A1b4b1e06e7ef4a2ab4CD8aC0A087D",
                "0x50FEEdF7fB2F511112287091819F21eb0F3Ce498",
            ],
            [0, 1, 2, 3],
            [9970, 500, 350, 1000]
        )
        const ret = await this.arbiter.checkUpkeep(jobId)
        expect(ret.upkeepNeeded).to.be.true
        await this.arbiter.performUpkeep(ret.performData)
    })
})

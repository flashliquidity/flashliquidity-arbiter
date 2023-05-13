import { ethers } from "hardhat"
import { expect } from "chai"
import { time } from "@nomicfoundation/hardhat-network-helpers"
import { ADDRESS_ZERO, LINKERC667, REGISTRY_ADDR, REGISTRAR_ADDR } from "./utilities"

describe("UpkeepsStation", function () {
    before(async function () {
        this.signers = await ethers.getSigners()
        this.governor = this.signers[0]
        this.bob = this.signers[1]
        this.dev = this.signers[2]
        this.minter = this.signers[3]
        this.arbiter = this.signers[4]
        this.bastion = this.signers[5]
        this.transferGovernanceDelay = 60
        this.toUpkeepAmount = ethers.utils.parseUnits("1.0", 18)
        this.createUpkeepAmount = ethers.utils.parseUnits("5.0", 18)
        this.UpkeepsStation = await ethers.getContractFactory("UpkeepsStationV3")
    })

    beforeEach(async function () {
        this.link = await ethers.getContractAt("LinkTokenInterface", LINKERC667)
        this.registry = await ethers.getContractAt("AutomationRegistryInterface", REGISTRY_ADDR)
        this.station = await this.UpkeepsStation.deploy(
            this.governor.address,
            this.arbiter.address,
            this.bastion.address,
            LINKERC667,
            REGISTRY_ADDR,
            REGISTRAR_ADDR,
            this.transferGovernanceDelay
        )
        await this.station.deployed()
    })

    it("Should allow only Governor to request governance transfer", async function () {
        await expect(this.station.connect(this.bob).setPendingGovernor(this.bob.address)).to.be
            .revertedWith("NotAuthorized()")
        expect(await this.station.pendingGovernor()).to.not.be.equal(this.bob.address)
        await this.station.connect(this.governor).setPendingGovernor(this.bob.address)
        expect(await this.station.pendingGovernor()).to.be.equal(this.bob.address)
        expect(await this.station.govTransferReqTimestamp()).to.not.be.equal(0)
    })

    it("Should not allow to set pendingGovernor to zero address", async function () {
        await expect(
            this.station.connect(this.governor).setPendingGovernor(ADDRESS_ZERO)
        ).to.be.revertedWith("ZeroAddress()")
    })

    it("Should allow to transfer governance only after min delay has passed from request", async function () {
        await this.station.connect(this.governor).setPendingGovernor(this.bob.address)
        await expect(this.station.transferGovernance()).to.be.revertedWith("TooEarly()")
        await time.increase(this.transferGovernanceDelay)
        await this.station.transferGovernance()
        expect(await this.station.governor()).to.be.equal(this.bob.address)
    })

    it("Should allow only Governor to call initialize", async function () {
        await expect(
            this.station.connect(this.bob).initialize(this.createUpkeepAmount)
        ).revertedWith("NotAuthorized()")
    })

    it("Should allow only Governor to set minUpkeepBalance", async function () {
        await expect(
            this.station.connect(this.bob).setMinUpkeepBalance("2000000000000000000")
        ).revertedWith("NotAuthorized()")
        expect(await this.station.minUpkeepBalance()).to.not.be.equal("2000000000000000000")
        await this.station.connect(this.governor).setMinUpkeepBalance("2000000000000000000")
        expect(await this.station.minUpkeepBalance()).to.be.equal("2000000000000000000")
    })

    it("Should allow only Governor to set toUpkeepAmount", async function () {
        await expect(
            this.station.connect(this.bob).setToUpkeepAmount("1000000000000000000")
        ).revertedWith("NotAuthorized()")
        expect(await this.station.toUpkeepAmount()).to.not.be.equal("1000000000000000000")
        await this.station.connect(this.governor).setToUpkeepAmount("1000000000000000000")
        expect(await this.station.toUpkeepAmount()).to.be.equal("1000000000000000000")
    })

    it("Should allow only Governor to set minDelayNextRefuel", async function () {
        await expect(
            this.station.connect(this.bob).setToUpkeepAmount("1000000000000000000")
        ).revertedWith("NotAuthorized()")
        expect(await this.station.toUpkeepAmount()).to.not.be.equal("1000000000000000000")
        await this.station.connect(this.governor).setToUpkeepAmount("1000000000000000000")
        expect(await this.station.toUpkeepAmount()).to.be.equal("1000000000000000000")
    })
})

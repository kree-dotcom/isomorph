const { expect } = require("chai");
const { ethers } = require("hardhat");
const { helpers } = require("../testHelpers.js")


describe("Unit test: Treasury contract", function () {
  let snapshotId;
  const provider = ethers.provider;

  before(async function () {
      moUSDcontract = await ethers.getContractFactory("TESTmoUSDToken");
      ISOcontract = await ethers.getContractFactory("isoToken");
      treasuryContract = await ethers.getContractFactory("Treasury");
      moUSD = await moUSDcontract.deploy();
      ISO = await ISOcontract.deploy(1);
      treasury = await treasuryContract.deploy(moUSD.address, ISO.address); 
  })

  beforeEach(async () => {
    snapshotId = await helpers.snapshot(provider);
    //console.log('Snapshotted at ', await provider.getBlockNumber());
  });

  afterEach(async () => {
    await helpers.revertChainSnapshot(provider, snapshotId);
    //console.log('Reset block heigh to ', await provider.getBlockNumber());
  });

  describe("Constructor", function () {
      it("should set up constants to default states", async function() {
          expect( await treasury.lastCall() ).to.equal(0);
          expect( await treasury.oneWeek() ).to.equal(60*60*24*7);
      });
  })

  describe("distributeFunds", function () {
      it("should fail if called less than a week since last call", async function() {
          await treasury.distributeFunds();
          await expect( treasury.distributeFunds()).to.be.revertedWith("Not enough time has past since last call!");
          
      });

      it("should be empty of all accrued moUSD on a successful call and update rewardRate correctly", async function() {
          await moUSD.transfer(treasury.address, 604800);
          expect( await moUSD.balanceOf(treasury.address) ).to.equal(604800);
          expect( await treasury.returnRewardRate()).to.equal(0);
          await treasury.distributeFunds();
          expect( await moUSD.balanceOf(treasury.address) ).to.equal(0);
          expect( await treasury.returnRewardRate() ).to.equal(1);
          
      });

      it("should emit a releaseFees event on success", async function() {
          const amount = await moUSD.balanceOf(treasury.address);
          const tx = await treasury.distributeFunds();
          const block = await ethers.provider.getBlock(tx.blockNumber);
          await expect(tx).to.emit(treasury, 'ReleaseFees').withArgs(amount, block.timestamp);
          
          
      });
  });
});

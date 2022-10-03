const { expect } = require("chai");
const { ethers } = require("hardhat");
const { helpers } = require("./testHelpers.js")

const BLOCK_HEIGHT = 13908578; //5th Jan 2022

const TWO_YEARS = 2*365*24*60*60; //2 years in seconds
const tokenAmount = ethers.utils.parseEther('10000000'); //10 million

describe("isoToken contract", function () {
  let snapshotId;
  const provider = ethers.provider;

  before(async function () {
      [owner, addr1, addr2, ...addrs] = await ethers.getSigners();
      ISOcontract = await ethers.getContractFactory("isoToken");
      
      ISO = await ISOcontract.connect(owner).deploy(tokenAmount);
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
          expect( await ISO.vestLength() ).to.equal(TWO_YEARS); 
          expect( await ISO.initialized() ).to.equal(true);
          expect( await ISO.allocatedTokens(owner.address)).to.equal(tokenAmount);
      });
  })

  describe("claimTokens", function () {
      it("should allocate freed tokens to valid users who call", async function() {
          const beforeISOBalance = await ISO.balanceOf(owner.address);
          helpers.timeSkip(24*60*60) //1 day
          const tx = await ISO.connect(addr1).claimTokens();
          const block = await ethers.provider.getBlock(tx.blockNumber);
          const freedTokens = await ISO.tokensClaimable(owner.address, block.timestamp);
          expect(beforeISOBalance).to.equal(0);
          await ISO.connect(owner).claimTokens();
          const afterISOBalance = await ISO.balanceOf(owner.address);
          const expectedBalance = beforeISOBalance.add(freedTokens);
          //check for deviations larger than 1/1000th
          expect(afterISOBalance).to.be.closeTo(expectedBalance, expectedBalance.div(1000) );
      });

      //inherit the ISOtoken with a test SC and do this atomically too
      it("should allocate almost nothing if called twice at the roughly the same time", async function() {
        helpers.timeSkip(24*60*60) //1 day
        const beforeISOBalance = await ISO.balanceOf(owner.address);
        expect(beforeISOBalance).to.equal(0);
        await ISO.connect(owner).claimTokens();
        const afterISOBalance = await ISO.balanceOf(owner.address);
        await ISO.connect(owner).claimTokens();
        const finalISOBalance = await ISO.balanceOf(owner.address);
        //check for deviations larger than 1/1000th
        expect(finalISOBalance).to.be.closeTo(afterISOBalance, afterISOBalance.div(1000));
    });

    it("should allocate almost the same if called after equal time lengths", async function() {
      helpers.timeSkip(24*60*60) //1 day
      const beforeISOBalance = await ISO.balanceOf(owner.address);
      expect(beforeISOBalance).to.equal(0);
      await ISO.connect(owner).claimTokens();
      const afterISOBalance = await ISO.balanceOf(owner.address);
      helpers.timeSkip(24*60*60) //1 day
      await ISO.connect(owner).claimTokens();
      const finalISOBalance = await ISO.balanceOf(owner.address);
      const differenceOfBalances = finalISOBalance.sub(afterISOBalance);
      //check for deviations larger than 1/1000th
      expect(differenceOfBalances).to.be.closeTo(afterISOBalance, afterISOBalance.div(1000));
  });

  it("should allocate entire allocation to valid users over time", async function() {
    helpers.timeSkip(24*60*60) //1 day
    const beforeISOBalance = await ISO.balanceOf(owner.address);
    expect(beforeISOBalance).to.equal(0);
    await ISO.connect(owner).claimTokens();
    const ISOBalance1 = await ISO.balanceOf(owner.address);
    const amountOfDays = 364 //changing this varies how many days pass in each step
    helpers.timeSkip(amountOfDays*24*60*60) //364 day
    await ISO.connect(owner).claimTokens();
    const ISOBalance2 = await ISO.balanceOf(owner.address);
    const isolatedBalance = ISOBalance2.sub(ISOBalance1);
    const expectedBalance = ISOBalance1.mul(amountOfDays);
    //check for deviations larger than 1/1000th
    expect(isolatedBalance).to.be.closeTo(expectedBalance, expectedBalance.div(1000));
    helpers.timeSkip((730-amountOfDays-1)*24*60*60)
    await ISO.connect(owner).claimTokens()
    const finalISOBalance = await ISO.balanceOf(owner.address);
    expect(finalISOBalance).to.equal(tokenAmount);

});

      it("should allocate entire allocation to valid users after vest ends", async function() {
        const beforeISOBalance = await ISO.balanceOf(owner.address);
        expect(beforeISOBalance).to.equal(0);
        helpers.timeSkip(1000000000);
        const tx = await ISO.connect(addr1).claimTokens();
        const block = await ethers.provider.getBlock(tx.blockNumber);
        const freedTokens = await ISO.tokensClaimable(owner.address, block.timestamp);
        await ISO.connect(owner).claimTokens()
        const afterISOBalance = await ISO.balanceOf(owner.address);
        expect(afterISOBalance).to.equal(tokenAmount);
    });

      it("should allocate no tokens to invalid users who call", async function() {
          const tx = await ISO.connect(addr2).claimTokens();
          const block = await ethers.provider.getBlock(tx.blockNumber);
          const beforeISOBalance = await ISO.balanceOf(addr1.address);
          expect(beforeISOBalance).to.equal(0);
          const freedTokens = await ISO.tokensClaimable(addr1.address, block.timestamp);
          expect(freedTokens).to.equal(0);
          await ISO.connect(addr1).claimTokens()
          const afterISOBalance = await ISO.balanceOf(owner.address);
          expect(afterISOBalance).to.equal(beforeISOBalance+freedTokens);
      });
  });
});
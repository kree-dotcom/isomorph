const { addresses } = require("../test/deployedAddresses.js")
const { expect } = require("chai");
const { ethers } = require("hardhat");
const { helpers } = require("../test/testHelpers.js");
const { ABIs } = require("../test/abi.js")
//We fetch the Lyra deployment addresses using their own protocol SDK, details here https://docs.lyra.finance/developers/tools/protocol-sdk
const { getMarketDeploys } = require('@lyrafinance/protocol');

const ZERO_ADDRESS = ethers.constants.AddressZero;
//Vault identification Enum key
const SYNTH = 0;
const LYRA = 1;
const VELO = 2;

async function impersonateForToken(provider, receiver, ERC20, donerAddress, amount) {
  let tokens_before = await ERC20.balanceOf(receiver.address)
  await network.provider.request({
    method: "hardhat_impersonateAccount",
    params: [donerAddress], 
  });
  const signer = await provider.getSigner(donerAddress);
  await ERC20.connect(signer).transfer(receiver.address, amount);
  await network.provider.request({
    method: "hardhat_stopImpersonatingAccount",
    params: [donerAddress] 
  });
  let tokens_after = await ERC20.balanceOf(receiver.address)
  expect(tokens_after).to.equal(tokens_before.add(amount))
  
}

async function updateStaleGreeks(greekCache, liveBoardIDs, account){
  //helper function for updating greeks of live lyra option boards, this prevents errors with other calls.
  for (let i in liveBoardIDs){
    console.log("updating board ", liveBoardIDs[i])
    await greekCache.connect(account).updateBoardCachedGreeks(liveBoardIDs[i])
  }
}


/*
This script deploys the full Isomorph system and demonstrates the opening of a loan with each Vault
*/
async function main() {
    //grab the provider endpoint
    const provider = ethers.provider;

    //constants used for deployment
    let sUSDaddress = addresses.optimism.sUSD;
    let sETHaddress = addresses.optimism.sETH;
    let sBTCaddress = addresses.optimism.sBTC;
    let sAMM_USDC_sUSD_address = addresses.optimism.sAMM_USDC_sUSD
    let sUSD_Doner = addresses.optimism.sUSD_Doner
    let lyra_LP_Doner = addresses.optimism.Lyra_Doner
    let velo_AMM_Doner = addresses.optimism.sAMM_USDC_sUSD_Doner
    

    let sUSDCode = ethers.utils.formatBytes32String("sUSD");
    let sETHCode = ethers.utils.formatBytes32String("sETH");
    let sBTCCode = ethers.utils.formatBytes32String("sBTC");
    let lyra_ETH_LP_Code = ethers.utils.formatBytes32String("LyraETHLP");
    let lyra_BTC_LP_Code = ethers.utils.formatBytes32String("LyraBTCLP");
    let velo_sAMM_USDC_sUSD_code = ethers.utils.formatBytes32String("VelosAMMUSDCSUSD");
    const MINTER = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("MINTER_ROLE"));
    const BASE = ethers.utils.parseEther("1");
    const testnetTimelock = 30 //3s timelock for testnet

    //Use the Lyra Protocol SDK to fetch their addresses
    let lyraMarket = getMarketDeploys('mainnet-ovm', 'sETH');
    const lyra_LP_Tokens_address = lyraMarket.LiquidityToken.address;
    const liquidity_pool_address = lyraMarket.LiquidityPool.address;
    const LyraGreekCache = lyraMarket.OptionGreekCache.address;
    const LyraOptionMarket = lyraMarket.OptionMarket.address;
    const LyraLPDoner = addresses.optimism.Lyra_Doner


    // match the addresses to their smart contracts so we can interact with them to update stale Lyra Greeks
    const lyraLiqPool = new ethers.Contract(lyra_LP_Tokens_address, ABIs.LyraLP, provider)
    const lyraLPToken = new ethers.Contract(liquidity_pool_address, ABIs.ERC20, provider)
    const greekCache = new ethers.Contract(LyraGreekCache, ABIs.GreekCache, provider)
    const optionMarket = new ethers.Contract(LyraOptionMarket, ABIs.OptionMarket, provider)
    let liveBoardIDs 


    const [deployer, alice] = await ethers.getSigners();

    

    const sUSD = new ethers.Contract(sUSDaddress, ABIs.ERC20, provider);
    const lyra_ETH_LP = new ethers.Contract(lyra_LP_Tokens_address, ABIs.ERC20, provider);
    const sAMM_USDC_sUSD = new ethers.Contract(sAMM_USDC_sUSD_address, ABIs.ERC20, provider);
  
    console.log("Deploying contracts with the account:", deployer.address);
  
    console.log("Account balance:", (await deployer.getBalance()).toString());
    
    //fetch contracts we are going to deploy
    //different collateral Vaults
    Vault_Synths = await ethers.getContractFactory("Vault_Synths");
    Vault_Lyra = await ethers.getContractFactory("Vault_Lyra");
    Vault_Velo = await ethers.getContractFactory("Vault_Velo");
    //core system
    isoUSDcontract = await ethers.getContractFactory("isoUSDToken");
    collateralContract = await ethers.getContractFactory("CollateralBook");
    //Velo-Deposit-Tokens, other contracts involved in this are deployed on constructing the Templater
    Templater = await ethers.getContractFactory("Templater")
    
    //Begin deployment
    isoUSD = await isoUSDcontract.deploy();
    console.log('Deployed isoUSD at: ', isoUSD.address);
    collateralBook = await collateralContract.deploy(); 
    console.log('Deployed Collateral Book at: ', collateralBook.address);
    //we use the deployer as the treasury for now
    vault_synth = await Vault_Synths.deploy(isoUSD.address, deployer.address, collateralBook.address);

    //Deploy Vault_Synth and add its address to relevant roles
    console.log('Deployed Synths Vault at: ', vault_synth.address);
    await collateralBook.addVaultAddress(vault_synth.address, SYNTH);
    console.log('Set Synth Vault address in collateral book');
    await isoUSD.proposeAddRole(vault_synth.address, MINTER);
    console.log('Proposed Synth Vault as minter in MoUSD');
    await helpers.timeSkip(testnetTimelock);
    await isoUSD.addRole(vault_synth.address, MINTER)
    
    //Add Vault_Synth collaterals
    const sETHMinMargin = ethers.utils.parseEther("2.0");
    const sETHLiqMargin = ethers.utils.parseEther("1.2");
    const sETHInterest = ethers.utils.parseEther("1.00000180"); // 37.04% annualized, excessive to expected value for test purposes
    
    const sBTCMinMargin = ethers.utils.parseEther("1.9");
    const sBTCLiqMargin = ethers.utils.parseEther("1.25");
    const sBTCInterest = ethers.utils.parseEther("1.00000200"); // 41.96% annualized compounding every 180s

    //Please note in the mainnet deployment it is unlikely sUSD will be available as a collateral but it is useful for testing so we add it here
    const sUSDMinMargin = ethers.utils.parseEther("1.3");
    const sUSDLiqMargin = ethers.utils.parseEther("1.053");
    const sUSDInterest = ethers.utils.parseEther("1.00000010"); // 1.76% annualized compounding every 180s
    liq_return = await vault_synth.LIQUIDATION_RETURN();
    
    
    await collateralBook.connect(deployer).addCollateralType(
      sETHaddress, 
      sETHCode, 
      sETHMinMargin, 
      sETHLiqMargin, 
      sETHInterest, 
      SYNTH, 
      ZERO_ADDRESS
      );
    console.log('Added sETH as collateral to CollateralBook');
    await collateralBook.connect(deployer).addCollateralType(
      sBTCaddress, 
      sBTCCode, 
      sBTCMinMargin, 
      sBTCLiqMargin, 
      sBTCInterest, 
      SYNTH, 
      ZERO_ADDRESS
      );
    console.log('Added sBTC as collateral to CollateralBook');
    await collateralBook.connect(deployer).addCollateralType(
      sUSDaddress, 
      sUSDCode, 
      sUSDMinMargin, 
      sUSDLiqMargin, 
      sUSDInterest, 
      SYNTH, 
      ZERO_ADDRESS
      );
    console.log('Added sUSD as collateral to CollateralBook');

    //Then deploy Vault_Lyra
    //Please see Vault_Lyra.js integration tests for testing Lyra collateral 
    //as Lyra has a lot of conditions that will break if you try to timeskip 
     
    vault_lyra = await Vault_Lyra.deploy(isoUSD.address, deployer.address, collateralBook.address);
    console.log('Deployed Lyra Vault');

    await collateralBook.addVaultAddress(vault_lyra.address, LYRA);
    console.log('Set Lyra Vault address in collateral book');
    await isoUSD.proposeAddRole(vault_lyra.address, MINTER);
    console.log('Proposed Lyra Vault as minter in MoUSD');
    await helpers.timeSkip(testnetTimelock);
    await isoUSD.addRole(vault_lyra.address, MINTER)

    //Add Lyra Liquidity Token as collateral
    
    lyraMinMargin = ethers.utils.parseEther("1.5"); //minimum opening ratio 
    lyraLiqMargin = ethers.utils.parseEther("1.15"); // ratio at which the loan can be liquidated by anyone
    lyraInterest = ethers.utils.parseEther("1.00000020"); // ~3.56% annualized compounding, 

    await collateralBook.connect(deployer).addCollateralType(
      lyra_LP_Tokens_address, 
      lyra_ETH_LP_Code, 
      lyraMinMargin, 
      lyraLiqMargin, 
      lyraInterest, 
      LYRA, 
      liquidity_pool_address);
  console.log('Added Lyra Liquidity Pool Tokens as collateral to Vault');    

    //Then deploy Vault_Velo
     
    vault_velo = await Vault_Velo.deploy(isoUSD.address, deployer.address, collateralBook.address);
    console.log('Deployed Velodrome Vault');
    
    await collateralBook.addVaultAddress(vault_velo.address, VELO);
    console.log('Set Velo Vault address in collateral book');
    await isoUSD.proposeAddRole(vault_velo.address, MINTER);
    console.log('Proposed Velo Vault as minter in MoUSD');
    await helpers.timeSkip(testnetTimelock);
    await isoUSD.addRole(vault_velo.address, MINTER)

    //Deploy Velo-Deposit-Tokens for USDC/sUSD Velodrome pair

    tokenA = addresses.optimism.USDC //USDC
    tokenB = addresses.optimism.sUSD //sUSD
    AMMToken_address = addresses.optimism.sAMM_USDC_sUSD
    voter = addresses.optimism.Velo_Voter
    router = addresses.optimism.Router
    pricefeed_address = addresses.optimism.Chainlink_SUSD_Feed
    
    templater = await Templater.deploy(
        tokenA,
        tokenB,
        true,
        AMMToken_address,
        voter,
        router,
        pricefeed_address
        )
    
    const depositReceipt_address = await templater.depositReceipt()
    const depositReceipt = new ethers.Contract(depositReceipt_address, ABIs.ERC721, provider);
    const veloMinMargin = ethers.utils.parseEther("1.3");
    const veloLiqMargin = ethers.utils.parseEther("1.1");
    const veloInterest = ethers.utils.parseEther("1.00000010"); // 1.76% annualized compounding every 180s
    liq_return = await vault_velo.LIQUIDATION_RETURN();
        
    await collateralBook.connect(deployer).addCollateralType(
      depositReceipt.address,
      velo_sAMM_USDC_sUSD_code,
      veloMinMargin, 
      veloLiqMargin, 
      veloInterest, 
      VELO, 
      ZERO_ADDRESS);

    console.log('Added sAMM-USDC-sUSD as collateral to CollateralBook');

    //workaround due to Lyra & Velodrome token doners not having ETH and being a Smart Contract which cannot receive ETH via transfers
    deathSeedContract = await ethers.getContractFactory("TESTdeathSeed");
    deathSeed = await deathSeedContract.deploy()
    deathSeed.terminate(lyra_LP_Doner, {"value" : BASE}); //self destruct giving ETH to SC without receive.
    deathSeed2 = await deathSeedContract.deploy()
    deathSeed2.terminate(velo_AMM_Doner, {"value" : BASE}); 

    //Acquired collateral tokens to open loans with
    console.log("Borrowing Collaterals needed")
    let amount = ethers.utils.parseEther("1000");
    let velo_amount = ethers.utils.parseEther("0.01"); //this is worth roughly $22000
    await impersonateForToken(provider, alice, sUSD, sUSD_Doner, amount)
    await impersonateForToken(provider, alice, lyra_ETH_LP, lyra_LP_Doner, amount)
    await impersonateForToken(provider, alice, sAMM_USDC_sUSD, velo_AMM_Doner, velo_amount)

    //approve ERC20 transfer to Vault
    await sUSD.connect(alice).approve(vault_synth.address, amount)
    //Open a loan of 500 isoUSD using 1000 sUSD as collateral
    await vault_synth.connect(alice).openLoan(sUSD.address, amount, amount.div(2))
    console.log("Opened loan on Synth Vault with sUSD as collateral")

    /**
    * The Lyra Vault requires additional calls to update the Greeks cache of the collateral being used 
    * If you are not testing this collateral it is advisable to comment this section out as it can very slow on first call (~10min)
    */

    liveBoardIDs = await optionMarket.getLiveBoards();
    console.log("Updating stale lyra board Greeks.")
    console.log("Please wait this may take some time...")
    for (let i in liveBoardIDs){
      //this is very slow, comment out if not needed
      await greekCache.connect(deployer).updateBoardCachedGreeks(liveBoardIDs[i], {gasLimit: 9000000})
      }

    //approve ERC20 transfer to Vault
    await lyra_ETH_LP.connect(alice).approve(vault_lyra.address, amount)
    //Open a loan of 500 isoUSD using 1000 lyra ETH LP tokens as collateral
    await vault_lyra.connect(alice).openLoan(lyra_ETH_LP.address, amount, amount.div(2))
    console.log("Opened loan on Lyra Vault with Lyra ETH LP tokens as collateral")

    /**
     * End of Lyra section
     */
    
    //For Velodrome Vault we must first generate a Deposit Receipt NFT to use as loan collateral
    console.log("Creating Depositor for sAMM-USDC/sUSD")
    await templater.connect(alice).makeNewDepositor()
    const depositor_address =  await templater.UserToDepositor(alice.address)
    
    const depositor = new ethers.Contract(depositor_address, ABIs.Depositor, provider);
    await sAMM_USDC_sUSD.connect(alice).approve(depositor.address, velo_amount)
    
    //we deposit sAMM_USDC_sUSD with the deposit who sends it to the Velodrome Gauge and mints us a DepositReceipt NFT
    await depositor.connect(alice).depositToGauge(velo_amount)
    let NFT_id = 1 // this is the first NFT minted so we know this, you can also read it as output of the last call to depositor.
    
    //approve Deposit Receipt transfer to Vault
    await depositReceipt.connect(alice).approve(vault_velo.address, NFT_id)
    //Open a loan of 500 isoUSD using 1 DepositReceipt NFT worth roughly $22000 as collateral
    const addingCollateral = true
    await vault_velo.connect(alice).openLoan(depositReceipt.address, NFT_id, amount.div(2), addingCollateral)
    console.log("Opened loan on Velo Vault with sAMM-USDC/sUSD DepositReceipt as collateral")
    

  }
  
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
  
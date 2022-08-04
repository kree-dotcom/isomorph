//Price updating bot by  Isomorph.loans

const { ethers } = require("ethers");

require('dotenv').config()




async function cycleVirtualPrice() {
    //insert the address of the collateral you wish to update here
    collateral = "0xaA5068dC2B3AADE533d3e52C6eeaadC6a8154c57"

    //insert the number of times you wish to update for 
    //(if this is too high it will revert, you cannot update the virtual price into the future)
    rounds = 2

    //deployment address of CollateralBook contract
    address = "0x81a024d18Ab348065FC075e5B941E8dCdae7c016"

    //abi of the CollateralBook, reduced to minimum needed
    const abi = [
        "function updateVirtualPriceSlowly(address _collateralAddress, uint256 _cycles) external ",

        "function collateralProps(address collateral) external returns(bytes32 currencyKey, uint256 minOpeningMargin, uint256 liquidatableMargin, uint256 interestPer3Min, uint256 lastUpdateTime, uint256 virtualPrice, uint256 assetType  )"
    ]


    const provider = new ethers.providers.JsonRpcProvider(process.env.OPTIMISM_KOVAN_API_AND_KEY);
    signer = new ethers.Wallet(process.env.DEPLOYMENT_ACCOUNT, provider)
    collateralBook = new ethers.Contract(address, abi, provider);
    await collateralBook.connect(signer).updateVirtualPriceSlowly(collateral, rounds);
    console.log("Success!")
}

cycleVirtualPrice()


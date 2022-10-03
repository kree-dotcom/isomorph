pragma solidity =0.8.9;

import "../Vault_Lyra.sol";
//*************************************
//TEST CODE ONLY DO NOT USE ON MAINNET 
//*************************************
contract TEST_Vault_Lyra is Vault_Lyra {
    
    //This is a test contract only that enables us to forcibly change the virtualPrice
    //without accelerating the block timestamp, this enables us to test Lyra Collaterals
    //without Greeks going stale and being unupdatable due to time passed.

    constructor(
        address _moUSD, //moUSD address
        address _treasury, //treasury address
        address _collateralBook //collateral structure book address
        ) Vault_Lyra(_moUSD, _treasury, _collateralBook){}
        
    function TESTalterVirtualPrice(address _collateralAddress, uint256 newVirtualPrice) public {
        collateralBook.vaultUpdateVirtualPriceAndTime(_collateralAddress, newVirtualPrice, block.timestamp);
    }

}
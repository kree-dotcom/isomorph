pragma solidity =0.8.9;

import "../Vault_Synths.sol";
//*************************************
//TEST CODE ONLY DO NOT USE ON MAINNET 
//*************************************

contract TEST_Vault_Synths is Vault_Synths {
    
    //This is a test contract only that enables us to forcibly change the heartbeat time allowed for the chainlink oracle
    // this enables us to test long passages of time without the oracle reverting due to a stale price.

    constructor(
        address _isoUSD, //isoUSD address
        address _treasury, //treasury address
        address _collateralBook //collateral structure book address
        ) Vault_Synths(_isoUSD, _treasury, _collateralBook){}
        
    function TESTalterHeartbeatTime(uint256 _newHeartbeat) public onlyAdmin {
        HEARTBEAT = _newHeartbeat;
    }

}
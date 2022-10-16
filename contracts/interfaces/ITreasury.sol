//SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.9;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

//flesh out later on, use synthetix staking contract to enable staking of govt token then 
//paid dividends to stakers  
interface ITreasury { 
    

     
    //passthrough function for testing
     function returnRewardRate() external view returns(uint256);

    /**
      * @dev checks enough time has past since last distribution then sends accrued fees to staking contract if so
     **/
    function distributeFunds() external returns(uint256);

}
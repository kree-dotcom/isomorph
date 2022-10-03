//SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.9;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./helper/StakingRewards.sol";
import "./interfaces/ITreasury.sol";

//flesh out later on, use synthetix staking contract to enable staking of govt token then 
//paid dividends to stakers  
contract Treasury is ITreasury { 
    IERC20 moUSD; //stable
    IERC20 ISO; //govt token
    StakingRewards public feeStaking;
    uint256 public lastCall = 0;
    uint256 public constant oneWeek = 7 days;
    event ReleaseFees(uint256 FeesPaid, uint256 timestamp);

    constructor(address _moUSDaddr, address _ISOaddr) {
        moUSD = IERC20(_moUSDaddr);
        ISO = IERC20(_ISOaddr);
        feeStaking = new StakingRewards(address(this), address(this), _moUSDaddr,_ISOaddr);
    }

     
    //passthrough function for testing
     function returnRewardRate() external override view returns(uint256){
         return (feeStaking.rewardRate());
     }

    /**
      * @dev checks enough time has past since last distribution then sends accrued fees to staking contract if so
     **/
    function distributeFunds() external override returns(uint256){
        require(block.timestamp > (lastCall + oneWeek), "Not enough time has past since last call!");
        lastCall = block.timestamp;
        //logic here to send accrued funds to staking contract
        uint256 treasuryBalance = moUSD.balanceOf(address(this));
        bool success = moUSD.transfer(address(feeStaking), treasuryBalance);
        require(success, "moUSD transfer failed");
        feeStaking.notifyRewardAmount(treasuryBalance);
        emit ReleaseFees(treasuryBalance, block.timestamp);
        return (treasuryBalance);
    }

}
pragma solidity =0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/IisoToken.sol";

contract isoToken is ERC20 {

    mapping(address => uint256) public lockedTokens; //currently locked tokens of a user
    mapping(address => uint256) public allocatedTokens; //total tokens allocated to a user
    mapping(address => uint256) public unlockedTokens; //tokens unlocked for a user
    mapping(address => uint256) public lastCallTime; //timestamp of last user claim
    uint256 public constant vestLength = 730 days; //2 years
    uint256 public vestEnd = block.timestamp + vestLength;
    bool public initialized = false;

    event AllocateTokens(address user, uint256 amount);

    constructor(uint256 _allocation) ERC20("Isomorph", "ISO"){
        allocateTokenShare(msg.sender, _allocation);
    }

    // make this take in an array of users and allocations and loop.
    //merge with constructor then delete the function & notInitialized bool.
    function allocateTokenShare(address _recipient, uint256 _allocation) internal{
        require(!initialized, "function already run before");
        allocatedTokens[_recipient] = _allocation;
        lockedTokens[_recipient] = _allocation;
        unlockedTokens[_recipient] = 0; //unnecessary but explicit
        lastCallTime[_recipient] = block.timestamp;
        emit AllocateTokens(_recipient, _allocation);
        initialized = true;
    }
    
    // @notice the user can supply anything for epochTime, however actual claims always use block.timestamp
    // @param _user address who would be claiming their token allocation
    // @param _epochTime unix timestamp that the user expects to claim at
    function tokensClaimable (address _user, uint256 _epochTime) public view returns(uint256){
        //if vesting time has expired send everything allocated to user 
        if(_epochTime >= vestEnd){
            return(lockedTokens[_user]);
        }
        //else send a linear proportion of allocation depending on time past since last call.
        else{
            uint256 timeElapsed = _epochTime - lastCallTime[_user];
            return( (allocatedTokens[_user] * timeElapsed) / vestLength);
        }
        
    }

    // @notice call this function to claim unlocked allocated tokens  
    function claimTokens() external returns (uint256){
        uint256 freedTokens = tokensClaimable(msg.sender, block.timestamp);
        lastCallTime[msg.sender] = block.timestamp;
        lockedTokens[msg.sender] -= freedTokens;
        unlockedTokens[msg.sender] += freedTokens;
        _mint(msg.sender, freedTokens);
        return(freedTokens);
    }

    
}
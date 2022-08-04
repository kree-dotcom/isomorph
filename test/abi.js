//ABIs required when pointing to existing smart contracts

const SynthSystem = [
    // Some details about the token
  "function suspendSynth(bytes32, uint256) external",
  "function resumeSynths(bytes32[]) external",
  "function synthSuspension(bytes32) external view returns(bool, uint248)"
  ];

const ERC20 = [
    // Some details about the token
  "function name() view returns (string)",
  "function symbol() view returns (string)",

  // Get the account balance
  "function balanceOf(address) view returns (uint)",

  // Send some of your tokens to someone else
  "function transfer(address to, uint amount)",
  "function approve(address spender, uint amount)",

  // An event triggered whenever anyone transfers to someone else
  "event Transfer(address indexed from, address indexed to, uint amount)"
  ];

  const LyraLP = [
    "function CBTimestamp() view returns (uint256)",
    "function poolHedger() view returns (address)"
  ];

  const GreekCache = [
    "function updateBoardCachedGreeks(uint256) external "
  ]

  const OptionMarket = [
    "function getLiveBoards() external view returns(uint256[] memory)"
  ]

  ABIs = {ERC20: ERC20, 
          SynthSystem: SynthSystem, 
          LyraLP :LyraLP, 
          GreekCache : GreekCache,
          OptionMarket : OptionMarket}
  module.exports = { ABIs }

  
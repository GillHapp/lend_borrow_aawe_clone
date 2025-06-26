// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {OwnerIsCreator} from "@chainlink/contracts/src/v0.8/shared/access/OwnerIsCreator.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/contracts/applications/CCIPReceiver.sol";
import {IERC20} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";

contract ProgrammableTokenTransfers is CCIPReceiver, OwnerIsCreator {
    using SafeERC20 for IERC20;
    error NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees);
    error NothingToWithdraw();
    error FailedToWithdrawEth(address owner, address target, uint256 value);
    error DestinationChainNotAllowed(uint64 destinationChainSelector);
    error SourceChainNotAllowed(uint64 sourceChainSelector);
    error SenderNotAllowed(address sender);
    error InvalidReceiverAddress();

    event MessageSent(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address receiver,
        string text,
        address token,
        uint256 tokenAmount,
        address feeToken,
        uint256 fees
    );

    event MessageReceived(
        bytes32 indexed messageId,
        uint64 indexed sourceChainSelector,
        address sender,
        string text,
        address token,
        uint256 tokenAmount
    );

    struct UserTokenReceipt {
    address tokenAddress;
    uint256 amount;
     bool claimed;
     bool repaid;
}

    mapping(address => UserTokenReceipt) private s_userReceipts;

    bytes32 private s_lastReceivedMessageId;
    address private s_lastReceivedTokenAddress;
    uint256 private s_lastReceivedTokenAmount;
    string private s_lastReceivedText;

    mapping(uint64 => bool) public allowlistedDestinationChains;
    mapping(uint64 => bool) public allowlistedSourceChains;
    mapping(address => bool) public allowlistedSenders;

    IERC20 private s_linkToken;

    constructor(address _router, address _link) CCIPReceiver(_router) {
        s_linkToken = IERC20(_link);
    }

    modifier onlyAllowlistedDestinationChain(uint64 _destinationChainSelector) {
        if (!allowlistedDestinationChains[_destinationChainSelector])
            revert DestinationChainNotAllowed(_destinationChainSelector);
        _;
    }

    modifier validateReceiver(address _receiver) {
        if (_receiver == address(0)) revert InvalidReceiverAddress();
        _;
    }

    modifier onlyAllowlisted(uint64 _sourceChainSelector, address _sender) {
        if (!allowlistedSourceChains[_sourceChainSelector])
            revert SourceChainNotAllowed(_sourceChainSelector);
        if (!allowlistedSenders[_sender]) revert SenderNotAllowed(_sender);
        _;
    }

    function allowlistDestinationChain(
        uint64 _destinationChainSelector,
        bool allowed
    ) external onlyOwner {  
        allowlistedDestinationChains[_destinationChainSelector] = allowed;
    }

    function allowlistSourceChain(
        uint64 _sourceChainSelector,
        bool allowed
    ) external onlyOwner {
        allowlistedSourceChains[_sourceChainSelector] = allowed;
    }

    function allowlistSender(address _sender, bool allowed) external onlyOwner {
        allowlistedSenders[_sender] = allowed;
    }


    event TokenDeposited(address indexed user, address token, uint256 amount);

    // Transfer the owed tokens from user to this contrac

  function depositRepaymentToken() external {
    UserTokenReceipt storage receipt = s_userReceipts[msg.sender];

    // require(!receipt.claimed, "Tokens already deposited");
    require(receipt.tokenAddress != address(0), "No token receipt found");
    require(receipt.amount > 0, "Invalid token amount");

    // Transfer the owed tokens from user (msg.sender) to this contract
    IERC20(receipt.tokenAddress).safeTransferFrom(
        msg.sender,
        address(this),
        receipt.amount
    );

    // Mark as claimed (i.e., repaid)
    receipt.repaid = true;

    emit TokenDeposited(msg.sender, receipt.tokenAddress, receipt.amount);
}




    function sendMessagePayLINK(
    uint64 _destinationChainSelector,
    address _token,
    address _receiver,
    string calldata _text
)
    external
    onlyAllowlistedDestinationChain(_destinationChainSelector)
    validateReceiver(_receiver)
    returns (bytes32 messageId)
{

    // Load the receipt for the sender
    UserTokenReceipt storage receipt = s_userReceipts[msg.sender];
     require(receipt.repaid, "Tokens not yet repaid to contract");
    // ✅ Ensure the user previously claimed tokens
    require(receipt.claimed, "Tokens must be claimed before sending");

    // ✅ Ensure the repayment matches what was received
    // require(receipt.tokenAddress, "Token address mismatch");
    // require(receipt.amount == _amount, "Token amount mismatch");

    // ✅ Build CCIP message
    Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(
        _receiver,
        _text,
        receipt.tokenAddress,
        receipt.amount,
        address(s_linkToken)
    );
// 0x599D57483AA8259B72E4D73DAF35F9c83d2115dD
// 0xf99CCb6471047A3f046B6b69b6570229eaF24789
    IRouterClient router = IRouterClient(this.getRouter());

    uint256 fees = router.getFee(_destinationChainSelector, evm2AnyMessage);

    // ✅ Ensure contract has enough LINK to pay fees
    if (fees > s_linkToken.balanceOf(address(this)))
        revert NotEnoughBalance(s_linkToken.balanceOf(address(this)), fees);

    // ✅ Approve LINK to pay fees
    s_linkToken.approve(address(router), fees);

    // ✅ Approve the tokens to be transferred by the router
    IERC20(_token).approve(address(router), receipt.amount);

    // ✅ Send the CCIP message
    messageId = router.ccipSend(_destinationChainSelector, evm2AnyMessage);

    // ✅ Emit event
    emit MessageSent(
        messageId,
        _destinationChainSelector,
        _receiver,
        _text,
        receipt.tokenAddress,
        receipt.amount,
        address(s_linkToken),
        fees
    );

    return messageId;
}


    // function sendMessagePayLINK(
    //     uint64 _destinationChainSelector,
    //     address _receiver,
    //     string calldata _text,
    //     address _token,
    //     uint256 _amount
    // )
    //     external
    //     onlyAllowlistedDestinationChain(_destinationChainSelector)
    //     validateReceiver(_receiver)
    //     returns (bytes32 messageId)
    // {
    //     Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(
    //         _receiver,
    //         _text,
    //         _token,
    //         _amount,
    //         address(s_linkToken)
    //     );

    //     IRouterClient router = IRouterClient(this.getRouter());

    //     uint256 fees = router.getFee(_destinationChainSelector, evm2AnyMessage);

    //     if (fees > s_linkToken.balanceOf(address(this)))
    //         revert NotEnoughBalance(s_linkToken.balanceOf(address(this)), fees);

    //     s_linkToken.approve(address(router), fees);
    //     IERC20(_token).approve(address(router), _amount);

    //     messageId = router.ccipSend(_destinationChainSelector, evm2AnyMessage);

    //     emit MessageSent(
    //         messageId,
    //         _destinationChainSelector,
    //         _receiver,
    //         _text,
    //         _token,
    //         _amount,
    //         address(s_linkToken),
    //         fees
    //     );

    //     return messageId;
    // }

    function sendMessagePayNative(
        uint64 _destinationChainSelector,
        address _receiver,
        string calldata _text,
        address _token,
        uint256 _amount
    )
        external
        onlyAllowlistedDestinationChain(_destinationChainSelector)
        validateReceiver(_receiver)
        returns (bytes32 messageId)
    {
        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(
            _receiver,
            _text,
            _token,
            _amount,
            address(0)
        );

        IRouterClient router = IRouterClient(this.getRouter());

        uint256 fees = router.getFee(_destinationChainSelector, evm2AnyMessage);

        if (fees > address(this).balance)
            revert NotEnoughBalance(address(this).balance, fees);

        IERC20(_token).approve(address(router), _amount);

        messageId = router.ccipSend{value: fees}(_destinationChainSelector, evm2AnyMessage);

        emit MessageSent(
            messageId,
            _destinationChainSelector,
            _receiver,
            _text,
            _token,
            _amount,
            address(0),
            fees
        );

        return messageId;
    }

    function getLastReceivedMessageDetails()
        public
        view
        returns (
            bytes32 messageId,
            string memory text,
            address tokenAddress,
            uint256 tokenAmount
        )
    {
        return (
            s_lastReceivedMessageId,
            s_lastReceivedText,
            s_lastReceivedTokenAddress,
            s_lastReceivedTokenAmount
        );
    }

    function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage)
        internal
        override
        onlyAllowlisted(
            any2EvmMessage.sourceChainSelector,
            abi.decode(any2EvmMessage.sender, (address))
        )
    {
        (address originalSender, string memory text) = abi.decode(
            any2EvmMessage.data,
            (address, string)
        );

        s_lastReceivedMessageId = any2EvmMessage.messageId;
        s_lastReceivedText = text;
        s_lastReceivedTokenAddress = any2EvmMessage.destTokenAmounts[0].token;
        s_lastReceivedTokenAmount = any2EvmMessage.destTokenAmounts[0].amount;

         s_userReceipts[originalSender] = UserTokenReceipt({
        tokenAddress: s_lastReceivedTokenAddress,
        amount: s_lastReceivedTokenAmount,
         claimed: false,
         repaid:false
    });

        emit MessageReceived(
            any2EvmMessage.messageId,
            any2EvmMessage.sourceChainSelector,
            originalSender,
            text,
            s_lastReceivedTokenAddress,
            s_lastReceivedTokenAmount
        );
    }

    function _buildCCIPMessage(
        address _receiver,
        string calldata _text,
        address _token,
        uint256 _amount,
        address _feeTokenAddress
    ) private view returns (Client.EVM2AnyMessage memory) {
       Client.EVMTokenAmount[]
            memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: _token,
            amount: _amount
        });

        return Client.EVM2AnyMessage({
            receiver: abi.encode(_receiver),
            data: abi.encode(msg.sender, _text), // ✅ sending msg.sender and text
            tokenAmounts: tokenAmounts,
            extraArgs: Client._argsToBytes(
                Client.GenericExtraArgsV2({
                    gasLimit: 200_000,
                    allowOutOfOrderExecution: true
                })
            ),
            feeToken: _feeTokenAddress
        });
    }

    receive() external payable {}

    function withdraw(address _beneficiary) public onlyOwner {
        uint256 amount = address(this).balance;
        if (amount == 0) revert NothingToWithdraw();
        (bool sent, ) = _beneficiary.call{value: amount}("");
        if (!sent) revert FailedToWithdrawEth(msg.sender, _beneficiary, amount);
    }

   function claimReceivedTokens(address user) external {
    UserTokenReceipt storage receipt = s_userReceipts[user];

    if (receipt.amount == 0) revert NothingToWithdraw();
    if (receipt.claimed) revert(); // ✅ Optional: prevent double-claim

    receipt.claimed = true; // ✅ Mark as claimed

    IERC20(receipt.tokenAddress).safeTransfer(user, receipt.amount);
}

function getUserReceipt(address user) external view returns (
    address token,
    uint256 amount,
    bool claimed
) {
    UserTokenReceipt memory receipt = s_userReceipts[user];
    return (receipt.tokenAddress, receipt.amount, receipt.claimed);
}

event CustomTokenTransferred(address indexed from, address indexed token, uint256 amount);

function transferCustomTokenToContract(address token, uint256 amount) external {
    require(token != address(0), "Invalid token address");
    require(amount > 0, "Amount must be greater than 0");

    // Transfer tokens from user to contract
    IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

    emit CustomTokenTransferred(msg.sender, token, amount);
}

}

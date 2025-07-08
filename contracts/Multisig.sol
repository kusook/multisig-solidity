// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;
contract Multisig {
    event Deposit(address indexed user, uint256 amount, uint256 balance);
    event Submit(address indexed owner, uint256 indexed index, address indexed to, uint256 value, bytes data, uint40 timestart, bytes32 uniqueHash);
    event Confirm(address indexed owner, uint256 indexed index);
    event Revoke(address indexed owner, uint256 indexed index);
    event Execute(address indexed owner, uint256 indexed index);
    event Expire(uint256 indexed index);

    address[] public owners;
    mapping(address => bool) isOwner;
    uint256 public immutable chainId;
    bool private _locked;

    struct Transaction{
        bool executed;
        bool expired;
        uint256 numConf;
        address to;
        uint256 value;
        bytes data;
        uint40 timestart;
        bytes32 uniqueHash;
    }
    Transaction[] public transactions;

    mapping(uint256 => mapping(address => bool)) public isConf;

    modifier onlyOwner() {require (isOwner[msg.sender], "not owner");_;}
    modifier notExecuted(uint256 index) {require(!transactions[index].executed, "already executed");_;}
    modifier txExists(uint256 index) {require(index < transactions.length, "tx doesn't exist.");_;}
    modifier notConfirmed(uint256 index) {require (!isConf[index][msg.sender], "tx already confirmed");_;}
    modifier notExpired(uint256 index) {
        Transaction storage t = transactions[index];
        require(!t.expired, "tx expired");
        require(block.timestamp <= t.timestart + 86400, "confirmation period expired");
        _;
    } 
    modifier nonReentrant() {
        require(!_locked, "No re-entrancy");
        _locked = true;
        _;
        _locked = false;
    }
    
    uint256 public numConfirmationsRequired;

    constructor(address[] memory _owners, uint256 _numConfirmationsRequired) {
        chainId = block.chainid;
        numConfirmationsRequired = _numConfirmationsRequired;
        require(_owners.length > 0, "owners required");
        require(_numConfirmationsRequired > 0 && _numConfirmationsRequired <= _owners.length, "invalid number of required confirmations");
        for (uint256 i = 0; i < _owners.length; i++) {
            address owner = _owners[i];
            require(owner != address(0), "invalid owner");
            require(!isOwner[owner], "owner not unique");
            isOwner[owner] = true;
            owners.push(owner);
        }
    }

    receive() external payable {
        emit Deposit(msg.sender, msg.value, address(this).balance);
    }

    function submitTx(address _to, uint256 _value, bytes memory _data) public onlyOwner {
        require(_to != address(0), "Zero address");
        uint256 index = transactions.length;
        uint40 time = uint40(block.timestamp);
        bytes32 txHash = keccak256(abi.encode(
            chainId,
            address(this),
            index,
            _to,
            _value,
            _data,
            time
        ));
        transactions.push(
            Transaction({
                to: _to,
                value: _value,
                data: _data,
                executed: false,
                expired: false,
                numConf: 0,
                timestart: time,
                uniqueHash: txHash
            })
        );
        emit Submit(msg.sender, index, _to, _value, _data, time, txHash);
    }
    function confirmTx(uint256 _index) public onlyOwner txExists(_index) notExecuted(_index) notConfirmed(_index) notExpired(_index) {
        Transaction storage transaction = transactions[_index];
        bytes32 expectedHash = keccak256(abi.encode(
            chainId,
            address(this),
            _index,
            transaction.to,
            transaction.value,
            transaction.data,
            transaction.timestart
        ));
        require(transaction.uniqueHash == expectedHash, "Transaction hash mismatch");
        transaction.numConf += 1;
        isConf[_index][msg.sender] = true;
        emit Confirm(msg.sender, _index);
    }
    function isContract(address addr) private view returns (bool) {
        uint size;
        assembly { size := extcodesize(addr) }
        return size > 0;
    }
    function executeTx(uint256 _index) public onlyOwner txExists(_index) notExpired(_index) nonReentrant() {
        Transaction storage transaction = transactions[_index];
        require(!transaction.executed, "already executed");
        require(transaction.numConf >= numConfirmationsRequired, "unable to complete tx");
        require(transaction.data.length == 0 || isContract(transaction.to), "data sent to EOU");
        transaction.executed = true;
        (bool success,) = transaction.to.call{value: transaction.value, gas: gasleft()}(transaction.data);
        require(success, "tx failed");
        emit Execute(msg.sender, _index);
    }
    function multicall(bytes[] calldata calls) external onlyOwner nonReentrant {
        for (uint i; i<calls.length; ++i) {
            (bool success,) = address(this).delegatecall(calls[i]);
            require(!success, "Multicall failed");
        }
    }
    function _expireTx(uint256 index) private {
        Transaction storage t = transactions[index];
        if (!t.executed && !t.expired) {
            t.expired = true;
            emit Expire(index);
        }
    }
    function expireTx(uint256 _index) external txExists(_index) {
        Transaction storage transaction = transactions[_index];
        require(!transaction.executed, "already executed");
        require(block.timestamp > transaction.timestart + 86400, "not expired");
        _expireTx(_index);
    }
    function revokeConf(uint256 _index) public onlyOwner txExists(_index) notExecuted(_index) notExpired(_index) {
        Transaction storage transaction = transactions[_index];
        require(isConf[_index][msg.sender], "not confirmed");
        transaction.numConf -= 1;
        isConf[_index][msg.sender] = false;
        emit Revoke(msg.sender, _index);
    }
    function getOwners() public view returns (address[] memory) {
        return owners;
    }
    function getTransaction(uint256 _index) public view returns (
        address to,
        uint256 value,
        bytes memory data,
        bool executed,
        bool expired,
        uint256 numConf
    ) {
        Transaction storage transaction = transactions[_index];
        return (
            transaction.to,
            transaction.value,
            transaction.data,
            transaction.executed,
            transaction.expired,
            transaction.numConf
        );
    }
    function getTransactionCount() public view returns (uint256) {
        return transactions.length;
    }
}
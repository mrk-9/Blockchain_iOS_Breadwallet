//
//  TokenListViewController.swift
//  breadwallet
//
//  Created by Adrian Corscadden on 2018-04-08.
//  Copyright © 2018 breadwallet LLC. All rights reserved.
//

import UIKit

enum TokenListType {
    case manage
    case add
    
    var title: String {
        switch self {
        case .manage:
            return S.TokenList.manageTitle
        case .add:
            return S.TokenList.addTitle
        }
    }
    
    var addTitle: String {
        switch self {
        case .manage:
            return S.TokenList.show
        case .add:
            return S.TokenList.add
        }
    }
    
    var removeTitle: String {
        switch self {
        case .manage:
            return S.TokenList.hide
        case .add:
            return S.TokenList.remove
        }
    }
}

class EditWalletsViewController : UIViewController {
    
    struct Wallet {
        var currency: CurrencyDef
        var isHidden: Bool
    }

    private let type: TokenListType
    private let kvStore: BRReplicatedKVStore
    private var metaData: CurrencyListMetaData
    private let localCurrencies: [CurrencyDef] = [Currencies.btc, Currencies.bch, Currencies.eth, Currencies.brd]
    private let tableView = UITableView()
    private let searchBar = UISearchBar()

    private var wallets = [Wallet]() {
        didSet { tableView.reloadData() }
    }

    private var allWallets = [Wallet]()

    init(type: TokenListType, kvStore: BRReplicatedKVStore) {
        self.type = type
        self.kvStore = kvStore
        self.metaData = CurrencyListMetaData(kvStore: kvStore)!
        super.init(nibName: nil, bundle: nil)
    }

    override func viewDidLoad() {
        view.backgroundColor = .darkBackground
        view.addSubview(tableView)
        tableView.backgroundColor = .darkBackground
        tableView.keyboardDismissMode = .interactive
        tableView.separatorStyle = .none
        tableView.rowHeight = 66.0
        tableView.constrain([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
        if #available(iOS 11.0, *) {
            tableView.constrain([
                tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)])
        } else {
            tableView.constrain([
                tableView.topAnchor.constraint(equalTo: topLayoutGuide.bottomAnchor)])
            automaticallyAdjustsScrollViewInsets = false
        }
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(TokenCell.self, forCellReuseIdentifier: TokenCell.cellIdentifier)

        if type == .manage {
            tableView.setEditing(true, animated: true)
            setupAddButton()
        }
        setupSearchBar()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        StoredTokenData.fetchTokens(callback: { [weak self] in
            guard let `self` = self else { return }
            self.metaData = CurrencyListMetaData(kvStore: self.kvStore)!
            switch self.type {
            case .add:
                self.setAddModel(storedCurrencies: $0.map{ ERC20Token(tokenData: $0) })
            case .manage:
                self.setManageModel(storedCurrencies: $0.map{ ERC20Token(tokenData: $0) })
            }
        })
        title = type.title
    }

    // MARK: - 
    
    private func setupSearchBar() {
        guard type == .add else { return }
        let headerView = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 48.0))
        tableView.tableHeaderView = headerView
        headerView.addSubview(searchBar)
        searchBar.delegate = self
        searchBar.constrain([
            searchBar.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            searchBar.centerYAnchor.constraint(equalTo: headerView.centerYAnchor)])
        searchBar.searchBarStyle = .minimal
        searchBar.barStyle = .black
        searchBar.isTranslucent = false
        searchBar.barTintColor = .darkBackground
        searchBar.placeholder = S.Search.search
    }

    private func setupAddButton() {
        let footerView = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 70.0))
        tableView.tableFooterView = footerView
        let addButton = UIButton.icon(image: #imageLiteral(resourceName: "add"), title: S.TokenList.addTitle)
        addButton.tintColor = .disabledWhiteText
        addButton.setTitleColor(.disabledWhiteText, for: .normal)
        footerView.addSubview(addButton)
        addButton.constrain(toSuperviewEdges: UIEdgeInsets.init(top: 10, left: 0, bottom: 10, right: 0))
        addButton.tap = {
            self.pushAddWallets()
        }
    }

    private func pushAddWallets() {
        let addWallets = EditWalletsViewController(type: .add, kvStore: kvStore)
        navigationController?.pushViewController(addWallets, animated: true)
    }

    private func setManageModel(storedCurrencies: [CurrencyDef]) {
        let allCurrencies: [CurrencyDef] = storedCurrencies + localCurrencies
        let enabledCurrencies = findCurrencies(inKeyList: metaData.enabledCurrencies, fromCurrencies: allCurrencies)
        let hiddenCurrencies = findCurrencies(inKeyList: metaData.hiddenCurrencies, fromCurrencies: allCurrencies)
        wallets = enabledCurrencies.map { Wallet(currency: $0, isHidden: false) } + hiddenCurrencies.map { Wallet(currency: $0, isHidden: true) }
    }

    private func setAddModel(storedCurrencies: [CurrencyDef]) {
        wallets = storedCurrencies.filter { !self.metaData.previouslyAddedTokenAddresses.contains(($0 as! ERC20Token).address)}.map{ Wallet(currency: $0, isHidden: true) }
        allWallets = wallets
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        reconcileChanges()
        title = ""
    }

    private func reconcileChanges() {
        switch type {
        case .add:
            addAddedTokens()
        case .manage:
            mergeChanges()
        }
    }

    private func editCurrency(identifier: String, isHidden: Bool) {
        wallets = wallets.map { wallet in
            if currencyMatchesCode(currency: wallet.currency, identifier: identifier) {
                return Wallet(currency: wallet.currency, isHidden: isHidden)
            } else {
                return wallet
            }
        }
        allWallets = allWallets.map { wallet in
            if currencyMatchesCode(currency: wallet.currency, identifier: identifier) {
                return Wallet(currency: wallet.currency, isHidden: isHidden)
            } else {
                return wallet
            }
        }
    }

    private func addAddedTokens() {
        let tokensToBeAdded: [ERC20Token] = allWallets.filter { $0.isHidden == false }.map{ $0.currency as! ERC20Token }
        var displayOrder = Store.state.displayCurrencies.count
        let newWallets: [String: WalletState] = tokensToBeAdded.reduce([String: WalletState]()) { (dictionary, currency) -> [String: WalletState] in
            var dictionary = dictionary
            dictionary[currency.code] = WalletState.initial(currency, displayOrder: displayOrder)
            displayOrder = displayOrder + 1
            return dictionary
        }
        metaData.addTokenAddresses(addresses: tokensToBeAdded.map{ $0.address })
        save()
        Store.perform(action: ManageWallets.addWallets(newWallets))
    }
    
    private func mergeChanges() {

        let oldWallets = Store.state.wallets
        var newWallets = [String: WalletState]()
        var displayOrder = 0
        wallets.forEach { entry in
            let currency = entry.currency
            let isHidden = entry.isHidden
            
            //Hidden local wallets get a displayOrder of -1
            let localCurrencyCodes = localCurrencies.map { $0.code.lowercased() }
            if localCurrencyCodes.contains(currency.code.lowercased()) {
                var walletState = oldWallets[currency.code]!
                if isHidden {
                    walletState = walletState.mutate(displayOrder: -1)
                } else {
                    walletState = walletState.mutate(displayOrder: displayOrder)
                    displayOrder = displayOrder + 1
                }
                newWallets[currency.code] = walletState

            //Hidden tokens, except for brd, get removed from the wallet state
            } else {
                if let walletState = oldWallets[currency.code] {
                    if isHidden {
                        newWallets[currency.code] = nil
                    } else {
                        newWallets[currency.code] = walletState.mutate(displayOrder: displayOrder)
                        displayOrder = displayOrder + 1
                    }
                } else {
                    if isHidden == false {
                        let newWalletState = WalletState.initial(currency, displayOrder: displayOrder)
                        displayOrder = displayOrder + 1
                        newWallets[currency.code] = newWalletState
                    }
                }
            }
        }

        //Save new metadata
        metaData.enabledCurrencies = wallets.compactMap {
            guard $0.isHidden == false else { return nil}
            if let token = $0.currency as? ERC20Token {
                return C.erc20Prefix + token.address
            } else {
                return $0.currency.code
            }
        }
        metaData.hiddenCurrencies = wallets.compactMap {
            guard $0.isHidden == true else { return nil}
            if let token = $0.currency as? ERC20Token {
                return C.erc20Prefix + token.address
            } else {
                return $0.currency.code
            }
        }
        save()

        //Apply new state
        Store.perform(action: ManageWallets.setWallets(newWallets))
    }
    
    private func save() {
        do {
            let _ = try kvStore.set(metaData)
        } catch let error {
            print("error setting wallet info: \(error)")
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension EditWalletsViewController : UITableViewDelegate, UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return wallets.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: TokenCell.cellIdentifier, for: indexPath) as? TokenCell else { return UITableViewCell() }
        cell.set(currency: wallets[indexPath.row].currency, listType: type, isHidden: wallets[indexPath.row].isHidden)
        cell.didAddIdentifier = { [unowned self] identifier in
            self.editCurrency(identifier: identifier, isHidden: false)
        }
        cell.didRemoveIdentifier = { [unowned self] identifier in
            self.editCurrency(identifier: identifier, isHidden: true)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCellEditingStyle {
        return .none
    }

    func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
        return false
    }

    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        let movedObject = wallets[sourceIndexPath.row]
        wallets.remove(at: sourceIndexPath.row)
        wallets.insert(movedObject, at: destinationIndexPath.row)
    }
}

extension EditWalletsViewController : UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if searchText == "" {
            wallets = allWallets
        } else {
            wallets = allWallets.filter {
                return $0.currency.name.lowercased().contains(searchText.lowercased()) || $0.currency.code.lowercased().contains(searchText.lowercased())
            }
        }
    }
}

extension EditWalletsViewController {
    private func findCurrencies(inKeyList keys: [String], fromCurrencies: [CurrencyDef]) -> [CurrencyDef] {
        return keys.compactMap { codeOrAddress in
            let codeOrAddress = codeOrAddress.replacingOccurrences(of: C.erc20Prefix, with: "")
            var currency: CurrencyDef? = nil
            fromCurrencies.forEach {
                if currencyMatchesCode(currency: $0, identifier: codeOrAddress) {
                    currency = $0
                }
            }
            assert(currency != nil || E.isTestnet)
            return currency
        }
    }

    private func currencyMatchesCode(currency: CurrencyDef, identifier: String) -> Bool {
        if currency.code.lowercased() == identifier.lowercased() {
            return true
        }
        if let token = currency as? ERC20Token {
            if token.address.lowercased() == identifier.lowercased() {
                return true
            }
        }
        return false
    }
}

struct StoredTokenData : Codable {
    let address: String
    let name: String
    let code: String
    let colors: [String]
    let decimal: String
}

extension StoredTokenData {
    static func fetchTokens(callback: @escaping ([StoredTokenData])->Void) {
        DispatchQueue.global(qos: .utility).async {
            do {
                let path = Bundle.main.path(forResource: "tokens", ofType: "json")
                let data = try Data(contentsOf: URL(fileURLWithPath: path!))
                var tokens: [StoredTokenData] = try JSONDecoder().decode([StoredTokenData].self, from: data)
                tokens.sort(by: { $0.code.lowercased() < $1.code.lowercased() })
                if E.isDebug {
                    tokens.append(StoredTokenData.tst)
                    tokens.append(StoredTokenData.viu)
                }
                if E.isTestnet {
                    //on testnet builds, remove the bundled ccc token as tokens.json doesn't support testnet
                    tokens = tokens.filter { $0.code.lowercased() != StoredTokenData.ccc.code.lowercased()}
                    //at the hardcoded ccc token for testnet builds
                    tokens.append(StoredTokenData.ccc)
                }
                DispatchQueue.main.async {
                    callback(tokens)
                }
            } catch let e {
                print("tokens json error: \(e)")
            }
        }
    }
}

extension StoredTokenData {
    static var tst: StoredTokenData {
        return StoredTokenData(address: E.isTestnet ?  "0x722dd3f80bac40c951b51bdd28dd19d435762180" : "0x3efd578b271d034a69499e4a2d933c631d44b9ad",
                               name: "Test Token",
                               code: "TST",
                               colors: ["2FB8E6", "2FB8E6"],
                               decimal: "18")
    }
    static var ccc: StoredTokenData {
        return StoredTokenData(address: E.isTestnet ?  "0x6e67ccd648244b3b8e2f56149b40ba8de9d79b09" : "0x9e3359f862b6c7f5c660cfd6d1aa6909b1d9504d",
                               name: E.isTestnet ? "Container Crypto Coin Test" : "Container Crypto Coin",
                               code: "CCC",
                               colors: ["95C121", "95C121"],
                               decimal: "18")
    }
    //this is a random token I was airdropped...using for testing
    static var viu: StoredTokenData {
        return StoredTokenData(address: "0x519475b31653e46d20cd09f9fdcf3b12bdacb4f5",
                               name: "VIU Token",
                               code: "VIU",
                               colors: ["2FB8E6", "2FB8E6"],
                               decimal: "18")
    }
}

import { preferenceService } from '../services/PreferenceService';
import { oauthService } from '../network/OAuthService';
import { authInterceptor } from '../network/AuthInterceptor';

export interface AccountOptions {
  id?: number
  name?: string
  account?: string
  accessToken?: string
  refreshToken?: string
  avatarUrl?: string
}

export class Account {
  id: number = 0
  name: string = ''
  account: string = ''
  accessToken: string = ''
  refreshToken: string = ''
  avatarUrl: string = ''

  constructor(options?: AccountOptions) {
    if (options) {
      this.id = options.id ?? 0
      this.name = options.name ?? ''
      this.account = options.account ?? ''
      this.accessToken = options.accessToken ?? ''
      this.refreshToken = options.refreshToken ?? ''
      this.avatarUrl = options.avatarUrl ?? ''
    }
  }
}

export class AccountStore {
  private static instance: AccountStore
  private accounts: Account[] = []
  private currentIndex: number = 0
  private isLoggedIn: boolean = false

  private constructor() {
    this.loadAccounts()
  }

  static getInstance(): AccountStore {
    if (!AccountStore.instance) {
      AccountStore.instance = new AccountStore()
    }
    return AccountStore.instance
  }

  private loadAccounts(): void {
    let data = preferenceService.getString('accounts', '[]')
    try {
      this.accounts = JSON.parse(data)
      this.currentIndex = preferenceService.getNumber('current_account_index', 0)
      this.isLoggedIn = this.accounts.length > 0
      if (this.isLoggedIn) {
        let current = this.accounts[this.currentIndex]
        authInterceptor.setTokens(current.accessToken, current.refreshToken)
      }
    } catch (e) {
      this.accounts = []
      this.isLoggedIn = false
    }
  }

  private saveAccounts(): void {
    preferenceService.setString('accounts', JSON.stringify(this.accounts))
    preferenceService.setNumber('current_account_index', this.currentIndex)
  }

  getIsLoggedIn(): boolean {
    return this.isLoggedIn
  }

  getCurrentAccount(): Account | null {
    if (this.accounts.length === 0) { return null }
    return this.accounts[this.currentIndex]
  }

  getAccounts(): Account[] {
    return this.accounts
  }

  async addAccount(code: string, codeVerifier: string): Promise<boolean> {
    try {
      let tokens = await oauthService.exchangeToken(code, codeVerifier)
      let accountOpts: AccountOptions = {
        accessToken: tokens.access_token,
        refreshToken: tokens.refresh_token
      }
      let account = new Account(accountOpts)
      this.accounts.push(account)
      this.currentIndex = this.accounts.length - 1
      this.isLoggedIn = true
      this.saveAccounts()
      authInterceptor.setTokens(tokens.access_token, tokens.refresh_token)
      AppStorage.setOrCreate('isLoggedIn', true)
      return true
    } catch (e) {
      console.error('Login failed: ' + e)
      return false
    }
  }

  async loginWithRefreshToken(refreshToken: string): Promise<boolean> {
    try {
      let tokens = await oauthService.refreshToken(refreshToken)
      let accountOpts: AccountOptions = {
        accessToken: tokens.access_token,
        refreshToken: tokens.refresh_token
      }
      let account = new Account(accountOpts)
      this.accounts.push(account)
      this.currentIndex = this.accounts.length - 1
      this.isLoggedIn = true
      this.saveAccounts()
      authInterceptor.setTokens(tokens.access_token, tokens.refresh_token)
      return true
    } catch (e) {
      console.error('Token login failed: ' + e)
      return false
    }
  }

  async refreshToken(): Promise<boolean> {
    let current = this.accounts[this.currentIndex]
    if (!current || !current.refreshToken) { return false }
    try {
      let tokens = await oauthService.refreshToken(current.refreshToken)
      current.accessToken = tokens.access_token
      current.refreshToken = tokens.refresh_token
      this.accounts[this.currentIndex] = current
      this.saveAccounts()
      authInterceptor.setTokens(tokens.access_token, tokens.refresh_token)
      return true
    } catch (e) {
      console.error('Token refresh failed: ' + e)
      return false
    }
  }

  logout(): void {
    this.accounts = []
    this.currentIndex = 0
    this.isLoggedIn = false
    this.saveAccounts()
    authInterceptor.clearTokens()
    AppStorage.setOrCreate('isLoggedIn', false)
  }

  switchAccount(index: number): void {
    if (index >= 0 && index < this.accounts.length) {
      this.currentIndex = index
      this.saveAccounts()
      let current = this.accounts[index]
      authInterceptor.setTokens(current.accessToken, current.refreshToken)
    }
  }
}

export const accountStore = AccountStore.getInstance()

import { preferenceService } from '../services/PreferenceService';
import { oauthService, CredentialInvalidError } from '../network/OAuthService';
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
  private needsRelogin: boolean = false

  private constructor() {
    this.loadAccounts()
    this.registerRefreshHandler()
  }

  static getInstance(): AccountStore {
    if (!AccountStore.instance) {
      AccountStore.instance = new AccountStore()
    }
    return AccountStore.instance
  }

  getNeedsRelogin(): boolean {
    return this.needsRelogin
  }

  clearNeedsRelogin(): void {
    this.needsRelogin = false
    AppStorage.setOrCreate('needsRelogin', false)
  }

  private registerRefreshHandler(): void {
    authInterceptor.setRefreshHandler(async () => {
      let success = await this.refreshToken()
      let current = this.getCurrentAccount()
      return current ? current.accessToken : ''
    })
    authInterceptor.setOnRefreshFailed(() => {
      // refreshToken 内部已按错误类型分类处理（凭证失效才登出），
      // 此处不再无差别 forceLogout，避免临时网络故障误登出
      console.error('Refresh handler threw unexpectedly')
    })
  }

  private forceLogout(): void {
    this.isLoggedIn = false
    AppStorage.setOrCreate('isLoggedIn', false)
  }

  private loadAccounts(): void {
    let data = preferenceService.getString('accounts', '[]')
    try {
      this.accounts = JSON.parse(data)
      this.currentIndex = preferenceService.getNumber('current_account_index', 0)
      this.isLoggedIn = this.accounts.length > 0
      if (this.isLoggedIn) {
        if (this.currentIndex >= this.accounts.length) {
          this.currentIndex = 0
        }
        let current = this.accounts[this.currentIndex]
        authInterceptor.setTokens(current.accessToken, current.refreshToken)
      }
      AppStorage.setOrCreate('isLoggedIn', this.isLoggedIn)
    } catch (e) {
      this.accounts = []
      this.isLoggedIn = false
      AppStorage.setOrCreate('isLoggedIn', false)
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

  getCurrentUserId(): number {
    let account = this.getCurrentAccount()
    return account ? account.id : 0
  }

  getAccounts(): Account[] {
    return this.accounts
  }

  async addAccount(code: string, codeVerifier: string): Promise<boolean> {
    try {
      let tokens = await oauthService.exchangeToken(code, codeVerifier)
      let accountOpts: AccountOptions = {
        id: Number(tokens.user.id),
        name: tokens.user.name,
        account: tokens.user.account,
        accessToken: tokens.access_token,
        refreshToken: tokens.refresh_token,
        avatarUrl: tokens.user.profile_image_urls?.px_170x170 ?? tokens.user.profile_image_urls?.px_50x50 ?? ''
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

  /** 成功返回空串，失败返回错误描述 */
  async loginWithRefreshToken(refreshToken: string): Promise<string> {
    try {
      let tokens = await oauthService.refreshToken(refreshToken)
      let accountOpts: AccountOptions = {
        id: Number(tokens.user.id),
        name: tokens.user.name,
        account: tokens.user.account,
        accessToken: tokens.access_token,
        refreshToken: tokens.refresh_token,
        avatarUrl: tokens.user.profile_image_urls?.px_170x170 ?? tokens.user.profile_image_urls?.px_50x50 ?? ''
      }
      let account = new Account(accountOpts)
      let existing = this.accounts.findIndex((a: Account) => a.id === account.id)
      if (existing >= 0) {
        this.accounts[existing] = account
        this.currentIndex = existing
      } else {
        this.accounts.push(account)
        this.currentIndex = this.accounts.length - 1
      }
      this.isLoggedIn = true
      this.saveAccounts()
      authInterceptor.setTokens(tokens.access_token, tokens.refresh_token)
      AppStorage.setOrCreate('isLoggedIn', true)
      return ''
    } catch (e) {
      console.error('Token login failed: ' + e)
      if (e instanceof CredentialInvalidError) {
        return 'Token 无效或已失效。注意：Refresh Token 为轮换制，若 pixez 在您导出后又运行过，导出的 Token 已被作废，请重新导出后立即使用'
      }
      return '网络请求失败，请检查网络后重试'
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
      this.clearNeedsRelogin()
      return true
    } catch (e) {
      if (e instanceof CredentialInvalidError) {
        // 凭证被服务端明确判定失效：置标记并登出，引导用户重新登录
        console.error('Credential invalid, relogin required: ' + e)
        this.needsRelogin = true
        AppStorage.setOrCreate('needsRelogin', true)
        this.forceLogout()
      } else {
        // 网络等临时错误：保持登录态，后续请求可再次尝试刷新
        console.error('Token refresh failed (temporary): ' + e)
      }
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

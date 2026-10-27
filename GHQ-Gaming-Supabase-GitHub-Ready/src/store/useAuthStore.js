import { create } from 'zustand'
import { authAPI } from '../services/api'
import { supabase } from '../services/supabase'

const readUser = () => {
  try { return JSON.parse(localStorage.getItem('ghq_user') || 'null') } catch { return null }
}

const save = (user, token, set) => {
  user ? localStorage.setItem('ghq_user', JSON.stringify(user)) : localStorage.removeItem('ghq_user')
  token ? localStorage.setItem('ghq_token', token) : localStorage.removeItem('ghq_token')
  set({ user, token, isLoggedIn: Boolean(user), isLoading: false, error: null })
}

const useAuthStore = create((set, get) => ({
  user: readUser(),
  token: localStorage.getItem('ghq_token'),
  isLoggedIn: Boolean(readUser()),
  isLoading: false,
  error: null,
  register: async (username, email, password, platform) => {
    set({ isLoading: true, error: null })
    try {
      const data = await authAPI.register({ username, email, password, platform })
      if (data.user) save(data.user, data.token, set); else set({ isLoading: false })
      return { success: true, requiresConfirmation: !data.user, message: data.message }
    } catch (error) {
      set({ isLoading: false, error: error.message })
      return { success: false, message: error.message }
    }
  },
  login: async (email, password) => {
    set({ isLoading: true, error: null })
    try {
      const data = await authAPI.login({ email, password })
      save(data.user, data.token, set)
      return { success: true }
    } catch (error) {
      set({ isLoading: false, error: error.message })
      return { success: false, message: error.message }
    }
  },
  logout: async () => { await supabase.auth.signOut(); save(null, null, set) },
  refreshUser: async () => {
    try {
      const data = await authAPI.getMe()
      const { data: session } = await supabase.auth.getSession()
      save(data.user, session.session?.access_token, set)
    } catch { if (get().isLoggedIn) save(null, null, set) }
  },
  updateUser: (updates) => save({ ...get().user, ...updates }, get().token, set),
  updateGollers: (gollers) => get().updateUser({ gollers }),
  clearError: () => set({ error: null }),
}))

supabase.auth.onAuthStateChange((_event, session) => {
  if (!session) save(null, null, useAuthStore.setState)
  else setTimeout(() => useAuthStore.getState().refreshUser(), 0)
})

export default useAuthStore

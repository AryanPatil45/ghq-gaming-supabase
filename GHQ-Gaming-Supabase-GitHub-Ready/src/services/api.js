import { supabase, unwrap } from './supabase'

const camel = (key) => key.replace(/_([a-z])/g, (_, c) => c.toUpperCase())
const snake = (key) => key.replace(/[A-Z]/g, c => `_${c.toLowerCase()}`)
const mapKeys = (value, fn) => {
  if (Array.isArray(value)) return value.map(v => mapKeys(v, fn))
  if (!value || typeof value !== 'object' || value instanceof Date) return value
  return Object.fromEntries(Object.entries(value).map(([k, v]) => [fn(k), mapKeys(v, fn)]))
}
const toApp = value => mapKeys(value, camel)
const toDb = value => mapKeys(value, snake)
const fail = error => { if (error) throw new Error(error.message || String(error)) }
const session = async () => unwrap(await supabase.auth.getSession()).session
const userId = async () => {
  const s = await session()
  if (!s) throw new Error('Please log in first')
  return s.user.id
}
const profile = async () => {
  const id = await userId()
  const { data, error } = await supabase.from('profiles').select('*').eq('id', id).single()
  fail(error)
  return toApp(data)
}
const moneyDisabled = () => Promise.reject(new Error('Real-money operations are disabled in this demo.'))

export const authAPI = {
  register: async ({ username, email, password, platform }) => {
    const { data, error } = await supabase.auth.signUp({
      email,
      password,
      options: { data: { username, platform: platform || '' } },
    })
    fail(error)
    if (!data.session) return { message: 'Account created. Check your email to confirm it.' }
    return { token: data.session.access_token, user: await profile(), message: 'Account created!' }
  },
  login: async ({ email, password }) => {
    const { data, error } = await supabase.auth.signInWithPassword({ email, password })
    fail(error)
    return { token: data.session.access_token, user: await profile() }
  },
  getMe: async () => ({ user: await profile() }),
  checkUsername: async (username) => {
    const { count, error } = await supabase.from('profiles').select('id', { count: 'exact', head: true }).ilike('username', username)
    fail(error)
    return { available: count === 0 }
  },
}

export const userAPI = {
  getProfile: async () => {
    const id = await userId()
    const { data, error } = await supabase.from('profiles').select('*, coin_transactions(*), user_achievements(*, achievement:achievements(*)), registrations(*, tournament:tournaments(id,name,game,status))').eq('id', id).single()
    fail(error)
    return { user: toApp(data) }
  },
  updateProfile: async body => {
    const id = await userId()
    const allowed = (({ username, platform, favoriteGame, avatar }) => ({ username, platform, favoriteGame, avatar }))(body)
    const { data, error } = await supabase.from('profiles').update(toDb(Object.fromEntries(Object.entries(allowed).filter(([,v]) => v !== undefined)))).eq('id', id).select().single()
    fail(error)
    return { message: 'Profile updated', user: toApp(data) }
  },
  getLeaderboard: async (game = 'all') => {
    let query = supabase.from('public_profiles').select('id,username,avatar,coins,wins,losses,favorite_game').order('coins', { ascending: false }).limit(50)
    if (game && game !== 'all') query = query.eq('favorite_game', game)
    const { data, error } = await query
    fail(error)
    return { leaderboard: toApp(data).map((u, i) => ({ ...u, rank: i + 1 })) }
  },
  getUserById: async id => {
    const { data, error } = await supabase.from('public_profiles').select('*').eq('id', id).single()
    fail(error)
    return { user: toApp(data) }
  },
}

export const tournamentAPI = {
  getAll: async (params = {}) => {
    let query = supabase.from('tournament_list').select('*')
    for (const [key, value] of Object.entries(params)) if (value && value !== 'all') query = query.ilike(snake(key), `%${value}%`)
    const { data, error } = await query
    fail(error)
    return { tournaments: toApp(data) }
  },
  getById: async id => {
    const { data: row, error } = await supabase.from('tournament_list').select('*').eq('id', id).single()
    fail(error)
    const [{ data: registrations, error: regError }, { data: matches, error: matchError }] = await Promise.all([
      supabase.from('registrations').select('*').eq('tournament_id', id),
      supabase.from('bracket_matches').select('*').eq('tournament_id', id).order('round').order('match_number'),
    ])
    fail(regError); fail(matchError)
    const data = { ...row, registrations: registrations || [], bracket_matches: matches || [] }
    const currentId = (await session())?.user?.id
    const registered = data.registrations?.some(r => r.user_id === currentId)
    if (data.status !== 'LIVE' || !registered) { data.room_id = null; data.room_password = null }
    return { tournament: { ...toApp(data), registeredPlayers: data.registrations?.length || 0, isRegistered: registered } }
  },
  getBracket: async id => {
    const { data, error } = await supabase.from('bracket_matches').select('*').eq('tournament_id', id).order('round').order('match_number')
    fail(error)
    const rounds = Object.values(toApp(data).reduce((all, m) => {
      all[m.round] ||= { name: m.roundName, matches: [] }
      all[m.round].matches.push({ id: m.id, player1: { name: m.player1Name, score: m.player1Score }, player2: { name: m.player2Name, score: m.player2Score }, status: m.status.toLowerCase() })
      return all
    }, {}))
    return { bracketData: { rounds } }
  },
  create: async body => {
    const { error } = await supabase.from('tournaments').insert(toDb(body))
    fail(error); return { message: 'Tournament created!', tournament: body }
  },
  update: async (id, body) => {
    const { error } = await supabase.from('tournaments').update(toDb(body)).eq('id', id)
    fail(error); return { message: 'Tournament updated', tournament: { id, ...body } }
  },
  setRoom: async () => { throw new Error('Room credentials are disabled until an Edge Function is configured.') },
  clearRoom: async () => ({ message: 'Room credentials are already disabled.' }),
  announceResults: async (id, body) => {
    const { data, error } = await supabase.rpc('announce_results', { p_tournament_id: Number(id), p_results: body.results })
    fail(error); return data
  },
}

export const economyAPI = {
  getBalance: async () => { const p = await profile(); return { coins: p.coins, gollers: p.gollers } },
  getTransactions: async () => {
    const id = await userId(); const { data, error } = await supabase.from('coin_transactions').select('*').eq('user_id', id).order('created_at', { ascending: false }); fail(error); return { transactions: toApp(data) }
  },
  claimDailyBonus: async () => { const { data, error } = await supabase.rpc('claim_daily_bonus'); fail(error); return data },
  getAchievements: async () => { const id = await userId(); const { data, error } = await supabase.from('user_achievements').select('*, achievement:achievements(*)').eq('user_id', id); fail(error); return { achievements: toApp(data) } },
  convertCoins: moneyDisabled,
  adminGrant: async body => { const { data, error } = await supabase.rpc('admin_grant_coins', { p_user_id: body.userId, p_amount: Number(body.amount), p_label: body.label || 'Admin grant' }); fail(error); return data },
}

export const gameAPI = {
  getSupportedGames: async () => ({ games: ['BGMI', 'Free Fire', 'Valorant', 'Call of Duty Mobile', 'PUBG', 'Fortnite'] }),
  getGameStats: async () => { const { data, error } = await supabase.from('user_game_profiles').select('game'); fail(error); const stats = Object.values(data.reduce((a,x) => { a[x.game] ||= { game:x.game, players:0 }; a[x.game].players++; return a },{})); return { stats } },
  getMyProfiles: async () => { const id = await userId(); const { data, error } = await supabase.from('user_game_profiles').select('*').eq('user_id', id); fail(error); return { profiles: toApp(data) } },
  getMyStats: async () => ({ stats: await profile() }),
  addGame: async body => { const { data, error } = await supabase.from('user_game_profiles').insert({ ...toDb(body), user_id: await userId() }).select().single(); fail(error); return { profile: toApp(data) } },
  updateGame: async (game, body) => { const { data, error } = await supabase.from('user_game_profiles').update(toDb(body)).eq('user_id', await userId()).eq('game', game).select().single(); fail(error); return { profile: toApp(data) } },
  removeGame: async game => { const { error } = await supabase.from('user_game_profiles').delete().eq('user_id', await userId()).eq('game', game); fail(error); return { message: 'Game removed' } },
  getUserProfiles: async id => { const { data, error } = await supabase.from('user_game_profiles').select('*').eq('user_id', id); fail(error); return { profiles: toApp(data) } },
  getGameLeaderboard: game => userAPI.getLeaderboard(game),
}

export const walletAPI = {
  getBalance: economyAPI.getBalance,
  getHistory: economyAPI.getTransactions,
  initiateTopUp: moneyDisabled,
  submitCode: moneyDisabled,
  getTopUpStatus: async () => ({ topUp: null }),
  joinTournament: async tournamentId => { const { data, error } = await supabase.rpc('join_free_tournament', { p_tournament_id: Number(tournamentId) }); fail(error); return data },
  getPending: async () => ({ topUps: [] }),
  verify: moneyDisabled,
}

export const withdrawAPI = { request: moneyDisabled, getMyRequests: async () => ({ requests: [] }), getAll: async () => ({ requests: [] }), markPaid: moneyDisabled, reject: moneyDisabled }

const crud = table => ({
  getAll: async () => { const { data, error } = await supabase.from(table).select('*').order('created_at', { ascending: false }); fail(error); return data },
  create: async body => { const { data, error } = await supabase.from(table).insert(toDb(body)).select().single(); fail(error); return toApp(data) },
  update: async (id, body) => { const { data, error } = await supabase.from(table).update(toDb(body)).eq('id', id).select().single(); fail(error); return toApp(data) },
  delete: async id => { const { error } = await supabase.from(table).delete().eq('id', id); fail(error); return { message: 'Deleted' } },
})
const ads = crud('advertisements')
export const adAPI = {
  getActive: async placement => { let q = supabase.from('advertisements').select('*').eq('is_active', true); if (placement) q = q.eq('placement', placement); const { data, error } = await q; fail(error); return { ads: toApp(data) } },
  getGateAds: async () => adAPI.getActive('gate'),
  getAll: async () => ({ ads: toApp(await ads.getAll()) }),
  create: async body => ({ ad: await ads.create(body) }), update: async (id, body) => ({ ad: await ads.update(id, body) }), delete: ads.delete,
}

const announcements = crud('announcements')
export const announcementAPI = {
  getAll: async () => { const now = new Date().toISOString(); const { data, error } = await supabase.from('announcements').select('*').eq('is_active', true).or(`expires_at.is.null,expires_at.gt.${now}`).order('pinned', { ascending: false }).order('created_at', { ascending: false }); fail(error); return { announcements: toApp(data) } },
  getAdmin: async () => ({ announcements: toApp(await announcements.getAll()) }),
  create: async body => ({ announcement: await announcements.create(body) }), update: async (id, body) => ({ announcement: await announcements.update(id, body) }), delete: announcements.delete,
}

export const configAPI = {
  getPublic: async () => { const { data, error } = await supabase.from('platform_config').select('key,value,label,category'); fail(error); return { config: Object.fromEntries(data.map(x => [x.key, x.value])) } },
  getAdmin: async () => { const { data, error } = await supabase.from('platform_config').select('*'); fail(error); return { config: toApp(data) } },
  save: async updates => { const rows = Object.entries(updates).map(([key, value]) => ({ key, value: String(value), label: key, category: 'general' })); const { error } = await supabase.from('platform_config').upsert(rows, { onConflict: 'key' }); fail(error); return { message: 'Settings saved' } },
}

export const fakeAPI = { fill: async () => { throw new Error('Fake-player generation is disabled.') }, clean: async () => ({ message: 'Nothing to clean' }) }
export default supabase

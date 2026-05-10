// Source: existing React + Firebase prototype to be ported to Flutter.
// Preserved verbatim for reference during the conversion.
// See ../docs/FLUTTER-CONVERSION.md for the port plan.

import React, { useState, useEffect, useCallback, useRef } from 'react';
import { Home, Trophy, Award, Bell, Heart, Star, Shield, Users, Sparkles, Moon, Sun, ChevronRight, Share2, Crown, Target } from 'lucide-react';

// Firebase Imports
import { initializeApp } from 'firebase/app';
import { getAuth, signInAnonymously, signInWithCustomToken, onAuthStateChanged } from 'firebase/auth';
import { getFirestore, collection, doc, setDoc, onSnapshot, increment } from 'firebase/firestore';

// Initialize Firebase securely
const firebaseConfig = typeof __firebase_config !== 'undefined' ? JSON.parse(__firebase_config) : {};
const app = initializeApp(firebaseConfig);
const auth = getAuth(app);
const db = getFirestore(app);
const appId = typeof __app_id !== 'undefined' ? __app_id : 'sallou-app-v2';

const DAILY_GLOBAL_GOAL = 1000000;

// Expanded Badges for long-term engagement
const BADGES = [
  { id: 1, title: 'مبتدئ', requirement: 10, icon: Star, color: 'text-blue-500', bg: 'bg-blue-100 dark:bg-blue-900/40' },
  { id: 2, title: 'مداوم', requirement: 100, icon: Heart, color: 'text-pink-500', bg: 'bg-pink-100 dark:bg-pink-900/40' },
  { id: 3, title: 'ذاكر لله', requirement: 500, icon: Shield, color: 'text-slate-500', bg: 'bg-slate-200 dark:bg-slate-700' },
  { id: 4, title: 'نور القلوب', requirement: 1000, icon: Sun, color: 'text-amber-500', bg: 'bg-amber-100 dark:bg-amber-900/40' },
  { id: 5, title: 'محب للنبي', requirement: 5000, icon: Award, color: 'text-emerald-500', bg: 'bg-emerald-100 dark:bg-emerald-900/40' },
  { id: 6, title: 'تاج الوقار', requirement: 10000, icon: Crown, color: 'text-purple-500', bg: 'bg-purple-100 dark:bg-purple-900/40' },
  { id: 7, title: 'رفيق الدرب', requirement: 50000, icon: Users, color: 'text-indigo-500', bg: 'bg-indigo-100 dark:bg-indigo-900/40' },
  { id: 8, title: 'الشفاعة المرجوة', requirement: 100000, icon: Trophy, color: 'text-yellow-500', bg: 'bg-yellow-100 dark:bg-yellow-900/40' },
];

// Sound Engine
const audioCtxRef = { current: null };
const initAudio = () => {
  if (!audioCtxRef.current) {
    const AudioContext = window.AudioContext || window.webkitAudioContext;
    if (AudioContext) audioCtxRef.current = new AudioContext();
  }
};

const playTapSound = () => {
  try {
    if (!audioCtxRef.current) return;
    const ctx = audioCtxRef.current;
    if (ctx.state === 'suspended') ctx.resume();

    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.type = 'sine';
    osc.frequency.setValueAtTime(800, ctx.currentTime);
    osc.frequency.exponentialRampToValueAtTime(300, ctx.currentTime + 0.1);

    gain.gain.setValueAtTime(0.05, ctx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.1);

    osc.connect(gain);
    gain.connect(ctx.destination);
    osc.start();
    osc.stop(ctx.currentTime + 0.1);
  } catch (e) { }
};

const playAchievementSound = () => {
  try {
    if (!audioCtxRef.current) return;
    const ctx = audioCtxRef.current;
    if (ctx.state === 'suspended') ctx.resume();

    const osc = ctx.createOscillator();
    const gainNode = ctx.createGain();

    osc.type = 'triangle';
    osc.frequency.setValueAtTime(523.25, ctx.currentTime);
    osc.frequency.setValueAtTime(659.25, ctx.currentTime + 0.1);
    osc.frequency.setValueAtTime(783.99, ctx.currentTime + 0.2);
    osc.frequency.setValueAtTime(1046.50, ctx.currentTime + 0.3);

    gainNode.gain.setValueAtTime(0.1, ctx.currentTime);
    gainNode.gain.exponentialRampToValueAtTime(0.00001, ctx.currentTime + 0.8);

    osc.connect(gainNode);
    gainNode.connect(ctx.destination);
    osc.start();
    osc.stop(ctx.currentTime + 0.8);
  } catch (err) {}
};

export default function App() {
  const [user, setUser] = useState(null);
  const [userName, setUserName] = useState(localStorage.getItem('sallou_username') || '');
  const [tempName, setTempName] = useState('');
  const [isDarkMode, setIsDarkMode] = useState(localStorage.getItem('sallou_theme') === 'dark');

  const [activeTab, setActiveTab] = useState('home');
  const [personalCount, setPersonalCount] = useState(parseInt(localStorage.getItem('sallou_local_count') || '0'));
  const [pendingClicks, setPendingClicks] = useState(0);
  const [globalCount, setGlobalCount] = useState(0);
  const [leaderboard, setLeaderboard] = useState([]);
  const [notifications, setNotifications] = useState([]);

  // Auth Initialization
  useEffect(() => {
    const initAuth = async () => {
      try {
        if (typeof __initial_auth_token !== 'undefined' && __initial_auth_token) {
          await signInWithCustomToken(auth, __initial_auth_token);
        } else {
          await signInAnonymously(auth);
        }
      } catch (err) {
        console.error("Auth error:", err);
      }
    };
    initAuth();
    const unsubscribe = onAuthStateChanged(auth, setUser);
    return () => unsubscribe();
  }, []);

  // Real-time Listeners
  useEffect(() => {
    if (!user || !userName) return;

    const globalRef = doc(db, 'artifacts', appId, 'public', 'data', 'stats', 'global');
    const unsubGlobal = onSnapshot(globalRef, (docSnap) => {
      if (docSnap.exists()) setGlobalCount(docSnap.data().totalCount || 0);
    });

    const lbColRef = collection(db, 'artifacts', appId, 'public', 'data', 'leaderboard');
    const unsubLb = onSnapshot(lbColRef, (snapshot) => {
      const usersList = [];
      snapshot.forEach(d => usersList.push({ id: d.id, ...d.data() }));
      usersList.sort((a, b) => b.count - a.count);
      setLeaderboard(usersList);

      // Sync local highest score to prevent data loss if localstorage cleared
      const myDoc = usersList.find(u => u.id === user.uid);
      if (myDoc && myDoc.count > personalCount) {
        setPersonalCount(myDoc.count);
        localStorage.setItem('sallou_local_count', myDoc.count.toString());
      }
    });

    return () => { unsubGlobal(); unsubLb(); };
  }, [user, userName]);

  // Debounced Data Push to Firestore
  useEffect(() => {
    if (!user || !userName) return;

    const pushData = async () => {
      if (pendingClicks === 0) return;
      const clicksToPush = pendingClicks;
      setPendingClicks(0);

      try {
        const globalRef = doc(db, 'artifacts', appId, 'public', 'data', 'stats', 'global');
        await setDoc(globalRef, { totalCount: increment(clicksToPush) }, { merge: true });

        const userRef = doc(db, 'artifacts', appId, 'public', 'data', 'leaderboard', user.uid);
        await setDoc(userRef, {
          name: userName,
          count: increment(clicksToPush),
          updatedAt: Date.now()
        }, { merge: true });
      } catch (err) {
        console.error("Error saving data:", err);
        setPendingClicks(prev => prev + clicksToPush); // Revert on fail
      }
    };

    const interval = setInterval(pushData, 2500); // Batch every 2.5s

    // Safety catch: save before user closes tab
    window.addEventListener('beforeunload', pushData);

    return () => {
      clearInterval(interval);
      window.removeEventListener('beforeunload', pushData);
      pushData(); // Push on unmount
    };
  }, [pendingClicks, user, userName]);

  const toggleTheme = () => {
    setIsDarkMode(prev => {
      const newTheme = !prev;
      localStorage.setItem('sallou_theme', newTheme ? 'dark' : 'light');
      return newTheme;
    });
  };

  const addNotification = useCallback((message, icon = Bell, type = 'normal') => {
    const id = Date.now();
    setNotifications(prev => [...prev, { id, message, icon, type }]);
    setTimeout(() => {
      setNotifications(prev => prev.filter(n => n.id !== id));
    }, type === 'success' ? 5000 : 3000);
  }, []);

  const handleTap = () => {
    initAudio(); // Required by browsers to init audio on first user interaction
    playTapSound();

    // Haptic Feedback for Mobile
    if (navigator.vibrate) navigator.vibrate(20);

    const newCount = personalCount + 1;
    setPersonalCount(newCount);
    setPendingClicks(prev => prev + 1);
    localStorage.setItem('sallou_local_count', newCount.toString());

    // Gamification Checks
    const unlockedBadge = BADGES.find(b => b.requirement === newCount);
    if (unlockedBadge) {
      playAchievementSound();
      if (navigator.vibrate) navigator.vibrate([100, 50, 100]); // Celebrate haptic
      addNotification(`تهانينا! حصلت على وسام: ${unlockedBadge.title} 🏆`, Award, 'success');
    }
  };

  const handleSaveName = () => {
    if (tempName.trim().length > 1) {
      const name = tempName.trim();
      localStorage.setItem('sallou_username', name);
      setUserName(name);
    }
  };

  // --- Onboarding Screen ---
  if (!userName) {
    return (
      <div dir="rtl" className="font-cairo min-h-screen bg-gradient-to-br from-teal-600 to-emerald-900 flex items-center justify-center p-4">
        <style>
          {`@import url('https://fonts.googleapis.com/css2?family=Cairo:wght@400;600;700;800&display=swap');
            .font-cairo { font-family: 'Cairo', sans-serif; }
          `}
        </style>
        <div className="bg-white rounded-3xl shadow-2xl p-8 max-w-sm w-full text-center animate-fade-in-down border-t-4 border-emerald-400">
          <div className="bg-emerald-50 w-24 h-24 rounded-full flex items-center justify-center mx-auto mb-6 shadow-inner">
            <Sparkles className="w-12 h-12 text-emerald-600 animate-pulse" />
          </div>
          <h1 className="text-3xl font-extrabold text-gray-800 mb-3 tracking-tight">صلوا عليه</h1>
          <p className="text-gray-500 mb-8 leading-relaxed text-sm">شارك في أعظم تحدي يومي. سجل اسمك وانضم لآلاف الذاكرين.</p>

          <input
            type="text"
            value={tempName}
            onChange={(e) => setTempName(e.target.value)}
            placeholder="اكتب اسمك للوحة الشرف..."
            className="w-full border-2 border-emerald-100 rounded-xl p-4 mb-4 focus:outline-none focus:border-emerald-500 focus:ring-4 focus:ring-emerald-50 transition-all text-gray-800 font-semibold text-center"
            onKeyDown={(e) => e.key === 'Enter' && handleSaveName()}
          />
          <button
            onClick={handleSaveName}
            disabled={tempName.trim().length < 2}
            className="w-full bg-emerald-600 hover:bg-emerald-700 disabled:bg-emerald-300 text-white font-bold py-4 rounded-xl transition-all shadow-lg hover:shadow-xl flex items-center justify-center gap-2 transform active:scale-95"
          >
            توكلنا على الله
            <ChevronRight className="w-5 h-5" />
          </button>
        </div>
      </div>
    );
  }

  // --- Main App Interface ---
  return (
    <div dir="rtl" className={`font-cairo min-h-screen flex justify-center transition-colors duration-500 ${isDarkMode ? 'dark bg-slate-950' : 'bg-slate-50'}`}>
      <style dangerouslySetInnerHTML={{__html: `
        @import url('https://fonts.googleapis.com/css2?family=Cairo:wght@400;600;700;800&display=swap');
        .font-cairo { font-family: 'Cairo', sans-serif; }
        @keyframes fade-in-down { 0% { opacity: 0; transform: translateY(-10px); } 100% { opacity: 1; transform: translateY(0); } }
        @keyframes ripple { 0% { transform: scale(1); opacity: 0.4; } 100% { transform: scale(2.5); opacity: 0; } }
        .animate-fade-in-down { animation: fade-in-down 0.4s cubic-bezier(0.16, 1, 0.3, 1) forwards; }
        .animate-ripple { animation: ripple 0.8s ease-out forwards; }
        .hide-scrollbar::-webkit-scrollbar { display: none; }
        .hide-scrollbar { -ms-overflow-style: none; scrollbar-width: none; }
      `}} />

      <div className="w-full max-w-md bg-white dark:bg-slate-900 min-h-screen shadow-[0_0_40px_rgba(0,0,0,0.05)] dark:shadow-none relative flex flex-col overflow-hidden transition-colors duration-500">

        {/* Header */}
        <header className="bg-gradient-to-l from-emerald-600 to-teal-700 dark:from-emerald-800 dark:to-teal-900 text-white p-4 pb-5 rounded-b-[2rem] shadow-md z-10 transition-colors">
          <div className="flex justify-between items-center px-2">
            <div>
              <h1 className="text-xl font-bold flex items-center gap-2 tracking-wide">
                <Sparkles className="w-5 h-5 text-yellow-300" />
                صلوا عليه
              </h1>
              <p className="text-xs text-emerald-100/80 mt-1 opacity-90">{userName}</p>
            </div>
            <div className="flex gap-1 bg-white/10 p-1 rounded-full backdrop-blur-sm">
              <button onClick={toggleTheme} className="p-2 hover:bg-white/20 rounded-full transition-colors">
                {isDarkMode ? <Sun className="w-5 h-5" /> : <Moon className="w-5 h-5" />}
              </button>
              <button
                onClick={async () => {
                  try {
                    if (navigator.share) {
                      await navigator.share({
                        title: 'تطبيق صلوا عليه',
                        text: `أنا وصلت لـ ${personalCount.toLocaleString('ar-EG')} صلاة على النبي اليوم! شاركني الأجر وتحداني في لوحة الشرف 🌟`,
                        url: window.location.href,
                      });
                    } else {
                      addNotification('انسخ الرابط وشاركه مع أصدقائك!', Share2);
                    }
                  } catch (e) {}
                }}
                className="p-2 hover:bg-white/20 rounded-full transition-colors"
              >
                <Share2 className="w-5 h-5" />
              </button>
            </div>
          </div>
        </header>

        {/* Notifications Toast */}
        <div className="absolute top-24 left-4 right-4 z-50 flex flex-col gap-2 pointer-events-none">
          {notifications.map(notif => (
            <div key={notif.id} className={`bg-white dark:bg-slate-800 border-r-4 shadow-xl rounded-xl p-3 flex items-center gap-3 animate-fade-in-down ${notif.type === 'success' ? 'border-yellow-400' : 'border-emerald-500'}`}>
              <div className={`p-2 rounded-full ${notif.type === 'success' ? 'bg-yellow-100 text-yellow-600 dark:bg-yellow-900/50' : 'bg-emerald-100 text-emerald-600 dark:bg-emerald-900/50'}`}>
                <notif.icon className="w-5 h-5" />
              </div>
              <p className="text-sm font-bold text-slate-700 dark:text-slate-200">{notif.message}</p>
            </div>
          ))}
        </div>

        {/* Main Content Area */}
        <main className="flex-1 overflow-y-auto pb-24 pt-2 px-4 hide-scrollbar">
          {activeTab === 'home' && (
            <HomeTab personalCount={personalCount} globalCount={globalCount + pendingClicks} onTap={handleTap} />
          )}
          {activeTab === 'leaderboard' && (
            <LeaderboardTab leaderboard={leaderboard} currentUserId={user?.uid} />
          )}
          {activeTab === 'profile' && (
            <ProfileTab personalCount={personalCount} userName={userName} />
          )}
        </main>

        {/* Bottom Navigation */}
        <nav className="absolute bottom-0 w-full bg-white/90 dark:bg-slate-900/90 backdrop-blur-md border-t border-slate-100 dark:border-slate-800 flex justify-around items-center p-2 pb-5 z-20 transition-colors">
          <NavButton icon={Home} label="الرئيسية" isActive={activeTab === 'home'} onClick={() => setActiveTab('home')} />
          <NavButton icon={Trophy} label="لوحة الشرف" isActive={activeTab === 'leaderboard'} onClick={() => setActiveTab('leaderboard')} />
          <NavButton icon={Award} label="إنجازاتي" isActive={activeTab === 'profile'} onClick={() => setActiveTab('profile')} />
        </nav>
      </div>
    </div>
  );
}

// --- Tabs Components ---

function HomeTab({ personalCount, globalCount, onTap }) {
  const [ripples, setRipples] = useState([]);

  const handleButtonTap = (e) => {
    // Generate Ripple Coordinates
    const rect = e.currentTarget.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;

    const newRipple = { id: Date.now(), x, y };
    setRipples(prev => [...prev, newRipple]);
    setTimeout(() => {
      setRipples(prev => prev.filter(r => r.id !== newRipple.id));
    }, 800);

    onTap();
  };

  const progress = Math.min((globalCount / DAILY_GLOBAL_GOAL) * 100, 100);

  // Find next badge
  const nextBadge = BADGES.find(b => b.requirement > personalCount) || BADGES[BADGES.length - 1];
  const prevBadgeReq = BADGES.slice().reverse().find(b => b.requirement <= personalCount)?.requirement || 0;
  const personalProgress = nextBadge.requirement === prevBadgeReq ? 100 : Math.min(((personalCount - prevBadgeReq) / (nextBadge.requirement - prevBadgeReq)) * 100, 100);

  return (
    <div className="flex flex-col items-center justify-between h-full py-4 space-y-6 animate-fade-in-down">

      {/* Global Goal Section */}
      <div className="w-full bg-gradient-to-br from-emerald-50 to-teal-50 dark:from-slate-800 dark:to-slate-800/80 rounded-2xl p-5 border border-emerald-100/50 dark:border-slate-700 shadow-sm relative overflow-hidden">
        <div className="absolute -right-4 -top-4 text-emerald-100 dark:text-slate-700/50 w-24 h-24 transform rotate-12">
          <Users className="w-full h-full" />
        </div>
        <div className="relative z-10">
          <div className="flex justify-between items-center mb-3">
            <span className="text-emerald-900 dark:text-emerald-300 font-bold flex items-center gap-2">
              الهدف الجماعي للأمة
            </span>
            <span className="text-emerald-600 dark:text-emerald-400 font-black bg-white dark:bg-slate-900 px-3 py-1 rounded-full text-xs shadow-sm">
              1,000,000
            </span>
          </div>
          <div className="w-full bg-white dark:bg-slate-900 rounded-full h-3.5 mb-2 overflow-hidden shadow-inner relative">
            <div
              className="bg-gradient-to-r from-teal-400 to-emerald-500 h-full rounded-full transition-all duration-1000 ease-out"
              style={{ width: `${progress}%` }}
            ></div>
          </div>
          <div className="flex justify-between items-center mt-2">
            <p className="text-xs text-slate-500 dark:text-slate-400 font-medium">تم جمع:</p>
            <p className="text-sm text-emerald-700 dark:text-emerald-400 font-bold flex items-center gap-1.5">
              <span className="relative flex h-2 w-2">
                <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
                <span className="relative inline-flex rounded-full h-2 w-2 bg-emerald-500"></span>
              </span>
              {globalCount.toLocaleString('ar-EG')} صلاة
            </p>
          </div>
        </div>
      </div>

      {/* Main Interactive Button Area */}
      <div className="relative flex flex-col items-center justify-center py-6 flex-1 w-full">
        {/* Decorative background rings */}
        <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
          <div className="w-72 h-72 rounded-full border-2 border-emerald-100 dark:border-slate-800 opacity-50 animate-[spin_10s_linear_infinite]"></div>
          <div className="absolute w-80 h-80 rounded-full border border-teal-50 dark:border-slate-800/50 opacity-50 animate-[spin_15s_linear_infinite_reverse]"></div>
        </div>

        <button
          onPointerDown={handleButtonTap}
          className="relative group w-64 h-64 rounded-full flex flex-col items-center justify-center bg-gradient-to-br from-emerald-400 to-teal-600 dark:from-emerald-600 dark:to-teal-800 text-white shadow-[0_20px_50px_-15px_rgba(16,185,129,0.5)] dark:shadow-[0_20px_50px_-15px_rgba(16,185,129,0.2)] focus:outline-none transform active:scale-[0.97] transition-transform duration-100 overflow-hidden"
        >
          {/* Ripples Container */}
          {ripples.map(ripple => (
            <span
              key={ripple.id}
              className="absolute bg-white rounded-full animate-ripple pointer-events-none"
              style={{ top: ripple.y - 10, left: ripple.x - 10, width: 20, height: 20 }}
            />
          ))}

          <div className="absolute inset-0 bg-gradient-to-t from-black/20 to-transparent"></div>

          <div className="relative z-10 flex flex-col items-center">
            <span className="text-6xl font-black mb-1 drop-shadow-lg tabular-nums tracking-tighter">
              {personalCount.toLocaleString('ar-EG')}
            </span>
            <span className="text-sm text-emerald-50/90 font-medium tracking-wide">صلاة اليوم</span>

            <div className="mt-6 w-16 h-1 bg-white/30 rounded-full overflow-hidden">
               <div className="h-full bg-white/80 rounded-full" style={{width: '50%'}}></div>
            </div>
            <p className="mt-3 text-xl font-bold opacity-95 tracking-widest drop-shadow-md">صَلِّ عَلَيْهِ</p>
          </div>
        </button>
      </div>

      {/* Next Target Indicator */}
      <div className="w-full px-4 mt-auto">
        <div className="bg-white dark:bg-slate-800/50 rounded-2xl p-4 border border-slate-100 dark:border-slate-700/50 flex items-center gap-4">
          <div className={`w-12 h-12 rounded-full ${nextBadge.bg} flex items-center justify-center flex-shrink-0`}>
             <nextBadge.icon className={`w-6 h-6 ${nextBadge.color}`} />
          </div>
          <div className="flex-1">
            <div className="flex justify-between items-center mb-1.5">
              <span className="text-xs font-bold text-slate-600 dark:text-slate-300">الهدف القادم: {nextBadge.title}</span>
              <span className="text-[10px] text-slate-400 font-medium">{nextBadge.requirement.toLocaleString('ar-EG')}</span>
            </div>
            <div className="w-full bg-slate-100 dark:bg-slate-700 rounded-full h-1.5">
               <div className="bg-emerald-500 h-1.5 rounded-full transition-all duration-300" style={{ width: `${personalProgress}%` }}></div>
            </div>
          </div>
        </div>
      </div>

    </div>
  );
}

function LeaderboardTab({ leaderboard, currentUserId }) {
  const topList = leaderboard.slice(0, 50); // Show top 50
  const myRankIndex = leaderboard.findIndex(u => u.id === currentUserId);
  const myRank = myRankIndex !== -1 ? myRankIndex + 1 : '-';
  const myData = myRankIndex !== -1 ? leaderboard[myRankIndex] : null;

  return (
    <div className="animate-fade-in-down pb-20 pt-2 flex flex-col h-full">
      <div className="text-center mb-6">
        <div className="inline-block p-3 bg-yellow-50 dark:bg-yellow-900/20 rounded-2xl mb-2">
          <Trophy className="w-10 h-10 text-yellow-500 drop-shadow-sm" />
        </div>
        <h2 className="text-2xl font-black text-slate-800 dark:text-white transition-colors">المتنافسون</h2>
        <p className="text-slate-500 dark:text-slate-400 text-sm mt-1">وفي ذلك فليتنافس المتنافسون</p>
      </div>

      <div className="bg-white dark:bg-slate-800 rounded-3xl border border-slate-100 dark:border-slate-700 shadow-sm overflow-hidden transition-colors flex-1 flex flex-col">
        {topList.length === 0 ? (
          <div className="p-8 text-center text-slate-400 dark:text-slate-500 flex-1 flex items-center justify-center">جاري تحميل البيانات...</div>
        ) : (
          <div className="overflow-y-auto flex-1 hide-scrollbar">
            {topList.map((user, index) => {
              const isMe = user.id === currentUserId;
              return (
                <div
                  key={user.id}
                  className={`flex items-center justify-between p-4 border-b border-slate-50 dark:border-slate-700/50 last:border-0 transition-colors ${isMe ? 'bg-emerald-50 dark:bg-emerald-900/20 sticky top-0 bottom-0 z-10 shadow-sm' : ''}`}
                >
                  <div className="flex items-center gap-3">
                    <div className={`w-8 h-8 rounded-full flex items-center justify-center font-bold text-sm ${
                      index === 0 ? 'bg-yellow-100 text-yellow-700 dark:bg-yellow-900/50' :
                      index === 1 ? 'bg-slate-200 text-slate-700 dark:bg-slate-700' :
                      index === 2 ? 'bg-amber-100 text-amber-800 dark:bg-amber-900/50' :
                      'bg-slate-50 text-slate-500 dark:bg-slate-800'
                    }`}>
                      {index === 0 ? '👑' : index + 1}
                    </div>
                    <div>
                      <p className={`font-bold text-sm ${isMe ? 'text-emerald-700 dark:text-emerald-400' : 'text-slate-800 dark:text-slate-200'}`}>
                        {user.name}
                      </p>
                    </div>
                  </div>
                  <div className="flex flex-col items-end">
                    <span className="text-emerald-600 dark:text-emerald-400 font-black text-sm tracking-tight">
                      {user.count.toLocaleString('ar-EG')}
                    </span>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>

      {/* Sticky Bottom Bar for user if not in top list viewport */}
      {myRankIndex > 49 && myData && (
        <div className="fixed bottom-[80px] left-4 right-4 bg-emerald-600 text-white rounded-2xl p-4 shadow-xl flex items-center justify-between z-30 animate-fade-in-down border-2 border-white dark:border-slate-800">
           <div className="flex items-center gap-3">
              <div className="w-8 h-8 rounded-full bg-white/20 flex items-center justify-center font-bold text-sm">
                {myRank}
              </div>
              <div>
                <p className="font-bold text-sm text-white">ترتيبك الحالي</p>
                <p className="text-xs text-emerald-100">{myData.name}</p>
              </div>
            </div>
            <span className="font-black tracking-tight bg-white/20 px-3 py-1 rounded-full text-sm">
              {myData.count.toLocaleString('ar-EG')}
            </span>
        </div>
      )}
    </div>
  );
}

function ProfileTab({ personalCount, userName }) {
  return (
    <div className="animate-fade-in-down pb-6 pt-2">
      {/* Profile Header */}
      <div className="bg-gradient-to-br from-teal-500 to-emerald-700 dark:from-slate-800 dark:to-slate-900 rounded-[2.5rem] p-6 text-center text-white mb-8 shadow-lg relative overflow-hidden">
        <div className="absolute -right-10 -top-10 opacity-10 w-40 h-40">
           <Award className="w-full h-full" />
        </div>
        <div className="relative z-10">
          <div className="w-20 h-20 bg-white/20 backdrop-blur-md rounded-full mx-auto mb-3 flex items-center justify-center border-2 border-white/50">
            <Target className="w-10 h-10 text-white" />
          </div>
          <h2 className="text-2xl font-black mb-1">{userName}</h2>
          <div className="bg-white/20 backdrop-blur-sm inline-block px-4 py-1.5 rounded-full">
            <p className="text-sm font-medium flex items-center gap-2">
              حصيلتك: <span className="font-black text-lg">{personalCount.toLocaleString('ar-EG')}</span>
            </p>
          </div>
        </div>
      </div>

      <div className="flex items-center justify-between mb-4 px-2">
        <h3 className="font-black text-slate-800 dark:text-white text-lg flex items-center gap-2">
          <Sparkles className="w-5 h-5 text-yellow-500" />
          سجل الأوسمة
        </h3>
        <span className="text-xs font-bold bg-emerald-100 text-emerald-700 dark:bg-slate-800 dark:text-emerald-400 px-3 py-1 rounded-full">
          {BADGES.filter(b => personalCount >= b.requirement).length} / {BADGES.length}
        </span>
      </div>

      <div className="grid grid-cols-2 gap-3">
        {BADGES.map((badge) => {
          const isUnlocked = personalCount >= badge.requirement;
          const progress = Math.min((personalCount / badge.requirement) * 100, 100);

          return (
            <div
              key={badge.id}
              className={`p-4 rounded-2xl border flex flex-col items-center text-center transition-all duration-300 relative overflow-hidden ${
                isUnlocked
                  ? `${badge.bg} border-transparent shadow-sm transform hover:-translate-y-1`
                  : 'bg-white dark:bg-slate-800/50 border-slate-100 dark:border-slate-700/50 opacity-80'
              }`}
            >
              {isUnlocked && <div className="absolute -right-4 -top-4 w-16 h-16 bg-white/20 rounded-full blur-xl"></div>}

              <badge.icon className={`w-8 h-8 mb-2 z-10 ${isUnlocked ? badge.color : 'text-slate-300 dark:text-slate-600'}`} />
              <h4 className={`font-bold text-sm z-10 ${isUnlocked ? 'text-slate-800 dark:text-slate-100' : 'text-slate-400'}`}>
                {badge.title}
              </h4>
              <p className={`text-[10px] z-10 mt-1 font-bold ${isUnlocked ? 'text-slate-600 dark:text-slate-300' : 'text-slate-400'}`}>
                {badge.requirement.toLocaleString('ar-EG')}
              </p>

              {!isUnlocked && (
                <div className="w-full bg-slate-100 dark:bg-slate-700 h-1 rounded-full mt-3 overflow-hidden">
                  <div
                    className="bg-emerald-400 h-full rounded-full transition-all duration-500"
                    style={{ width: `${progress}%` }}
                  ></div>
                </div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}

// --- Helper Components ---

function NavButton({ icon: Icon, label, isActive, onClick }) {
  return (
    <button
      onClick={onClick}
      className="relative flex flex-col items-center justify-center w-20 pt-1 focus:outline-none group"
    >
      <div className={`flex flex-col items-center transition-all duration-300 ${isActive ? '-translate-y-1' : ''}`}>
        <div className={`p-1.5 rounded-2xl transition-all duration-300 ${isActive ? 'bg-emerald-100 text-emerald-600 dark:bg-emerald-900/50 dark:text-emerald-400 shadow-inner' : 'text-slate-400 dark:text-slate-500 group-hover:text-emerald-500'}`}>
          <Icon className={`w-6 h-6 ${isActive ? 'fill-emerald-100 dark:fill-transparent' : ''}`} />
        </div>
        <span className={`text-[10px] mt-1 transition-all duration-300 ${isActive ? 'font-bold text-emerald-700 dark:text-emerald-400' : 'font-medium text-slate-500'}`}>
          {label}
        </span>
      </div>
      {isActive && (
        <span className="absolute -bottom-2 w-1 h-1 rounded-full bg-emerald-500 dark:bg-emerald-400"></span>
      )}
    </button>
  );
}

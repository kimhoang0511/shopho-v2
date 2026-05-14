import TopupPage from './TopupPage.jsx'
import PrivacyPage from './PrivacyPage.jsx'

export default function App() {
  const path = window.location.pathname

  if (path === '/privacy') {
    return <PrivacyPage />
  }

  return <TopupPage />
}
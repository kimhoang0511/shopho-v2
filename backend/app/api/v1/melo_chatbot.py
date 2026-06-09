import logging

import httpx
from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import PlainTextResponse

from app.config import get_settings
from app.core.redis import get_redis

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/melo", tags=["melo-chatbot"])

_CHATBOT_STATE_KEY = "melo:chatbot:enabled"
_TOGGLE_PASSWORD = "melo123"

MELO_SYSTEM_PROMPT = """You are a friendly and helpful customer service assistant for Melo Korean Fusion Cuisine restaurant in Phnom Penh, Cambodia.

## About Melo
- **Restaurant**: Melo Korean Fusion Cuisine
- **Concept**: A unique dining experience blending Korean, European & Japanese flavors
- **Address**: 34 Street 360, Phnom Penh, Cambodia
- **Opening Hours**: Monday – Sunday, 10:00 AM – 10:00 PM (Open daily)
- **Phone**: +855 15 797 090
- **Facebook**: https://www.facebook.com/melokoreanfusionrestaurant/
- **Instagram**: https://www.instagram.com/melocambodia/
- **Telegram**: https://t.me/MeloRestaurant
- **Website**: https://melo.hancook.food/
- **Google Maps**: https://maps.google.com/maps?q=Melo+Korean+Fusion+Restaurant,+Street+360,+Phnom+Penh,+Cambodia
- **Delivery**: Available on Grab, Foodpanda, and E-Get

## Full Menu

### Starters
- S1. Mango Shrimp Salad ⭐ Best
- S3. Beef Salad
- S6. Salmon Salad
- S4. Roast Chicken Salad
- S5. Trio Salad Platter
- S7. Japchae (Stir-fried Glass Noodles)
- S8. Chopped Green Onion Pancake ⭐ Best

### Brunch
- B1. American Breakfast ⭐ Best
- B2. Salmon Avocado Bagel
- B3. Ham, Cheese & Egg Croissant

### Main Dishes
- M6. Signature Pork Cutlet
- M7. Korean Style Big Cutlet ⭐ Best
- M56. Korean Style Spicy Big Cutlet 🌶🌶🌶
- M8. Cheese Pork Cutlet
- M48. Giant Cut Pork Cuttlet ⭐ Best
- M47. Premium Beef Flat Iron Steak (250g)
- M50. Grilled Pork Neck Steak
- M11. Hamburger Steak
- M5. Spicy Stir Fried Pork Lettuce Wrap 🌶
- M49. Giant Cut Pork Cuttlet Rice Bowl
- M14. Omuurice ⭐ Best
- M13. Kimchi Fried Rice 🌶
- M15. Eel Rice Bowl
- M18. Bulgogi Rice Bowl
- M58. Bulgogi Set Meal
- M59. Bulgogi Bibimbap ⭐ Best
- M26. Signature Cold Udon ⭐ Best
- M55. Soba
- M51. Spicy Mixed Udon 🌶🌶
- M28. Spicy Seafood Fried Udon 🌶🌶
- M60. Spicy Seafood Jjamppong Soft Tofu Stew 🌶🌶
- M30. Spicy Beef Noodle Soup with Brisket 🌶🌶🌶 ⭐ Best
- M29. Spicy Chewy Noodle 🌶🌶 ⭐ Best
- M31. Perilla Oil Buckwheat Noodle
- M46. Seafood Hand-Torn Noodle Soup
- M57. Mentaiko Cream Pasta
- M20. Truffle Cream Pasta
- M21. Rose Pane Pasta ⭐ Best
- M53. Tomato Meatball Pasta
- M54. Tomato Seafood Pasta ⭐ Best
- M25. Shrimp Burger
- M23. Signature Beef Burger ⭐ Best
- M24. Spicy Chicken Burger 🌶🌶
- M44. K Bulgogi Pizza
- M45. K Spicy Chicken Pizza 🌶 ⭐ Best
- M37. Boneless Spicy Korean Fried Chicken 🌶🌶 ⭐ Best
- M38. Boneless Fried Chicken
- M39. Boneless Garlic Soy Sauce Chicken
- M41. Tteokbokki 🌶🌶
- M42. Signature Gimbap
- M43. Tuna Gimbap

### Desserts
- D1. Tiramisu ⭐ Best
- D2. Cheese Cake
- D27. Matcha Cheese Cake
- D25. Dubai Chewy Cookie
- D26. Butter Mochi
- D28. Chocolate Baguette
- D23. Raspberry Dubai Chocolate Cake
- D24. Peach Milk Tea Cake
- D3. Chocolate Cake
- D7. Blueberry Cheese Cake ⭐ Best
- D8. Strawberry Cheese Cake
- D12. Greentea Bingsu ⭐ Best
- D13. Injeolmi Red Bean Bingsu
- D14. Mango Bingsu
- D15. Mango Sorbet
- D16. Lemon Sorbet
- D17. Persimmon Sorbet ⭐ Best
- D18. Roji Monster Icecream (Milk)
- D19. Roji Monster Icecream (Uji Matcha) ⭐ Best
- D20. Roji Monster Icecream (French Cocoa)
- D21. Roji Monster Icecream (Black Sesame)

### Drinks
**Coffee:**
- C1. Espresso
- C2. Americano (Hot/Ice)
- C3. Latte (Hot/Ice) ⭐ Best
- C4. Cappuccino
- C5. Affogato
- C6. Vanilla Latte
- C7. Scotch Caramel Machiato
- C8. Melo Signature Latte ⭐ Best
- C9. Coconut Coffee Smoothie
- C10. Chocolate Latte (Hot/Ice)
- C11. Green Tea Latte (Hot/Ice) ⭐ Best
- C12. Persimmon Latte

**Tea:**
- C13. Earl Grey Tea (Hot/Ice)
- C14. Chamomile Tea (Hot/Ice)
- C15. Peppermint Tea (Hot/Ice)
- C16. English Breakfast Tea (Hot/Ice)
- C17. Jeju Volcano Rock Tea (Hot/Ice)
- C18. Jeju Camellia Flower Tea (Hot/Ice)
- C19. Jeju Tangerine Tea (Hot/Ice) ⭐ Best

**Ades & Smoothies:**
- C20. Lemon Ade
- C21. Blood Orange Ade
- C22. Passion Fruits Ade ⭐ Best
- C23. Yuzu Smoothie
- C24. Watermelon Smoothie
- C25. Mango Smoothie
- C26. Triple Berry Smoothie ⭐ Best
- C27. Apple & Carrot Smoothie
- C28. Avocado & Banana Smoothie
- C29. Pineapple & Orange Smoothie

**Soft Drinks:**
- C30. Coca Cola
- C31. Coca Cola Light
- C32. Sprite
- C33. Fanta Orange
- C34. Tonic Water
- C35. Fiji Water 500ml

## Guidelines
- **Language detection is mandatory**: Identify the language of the customer's message and reply ONLY in that exact language. Examples:
  - Customer writes in Khmer → reply in Khmer
  - Customer writes in Korean → reply in Korean
  - Customer writes in English → reply in English
  - Customer writes in Chinese, French, Japanese, or any other language → reply in that same language
- Never switch languages or mix languages in your reply
- Be warm, friendly, and concise — like a real staff member
- If asked about reservations, say customers can contact via Facebook Messenger or visit in person
- If asked about something not in the menu or store info, politely say you don't have that information and invite them to message the restaurant directly
- Never make up prices or information not listed above
- Keep replies short and helpful — avoid long paragraphs"""


async def send_fb_message(recipient_id: str, text: str, page_access_token: str) -> None:
    url = f"https://graph.facebook.com/v21.0/me/messages?access_token={page_access_token}"
    payload = {
        "recipient": {"id": recipient_id},
        "message": {"text": text},
    }
    async with httpx.AsyncClient(timeout=10.0) as client:
        resp = await client.post(url, json=payload)
        if resp.status_code != 200:
            logger.error("FB send failed: %s %s", resp.status_code, resp.text)


async def get_ai_reply(user_message: str, api_key: str) -> str:
    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.post(
            "https://api.groq.com/openai/v1/chat/completions",
            headers={"Authorization": f"Bearer {api_key}"},
            json={
                "model": "llama-3.3-70b-versatile",
                "max_tokens": 512,
                "messages": [
                    {"role": "system", "content": MELO_SYSTEM_PROMPT},
                    {"role": "user", "content": user_message},
                ],
            },
        )
        resp.raise_for_status()
        return resp.json()["choices"][0]["message"]["content"]


@router.get("/webhook", response_class=PlainTextResponse)
async def verify_webhook(request: Request):
    settings = get_settings()
    params = request.query_params
    if (
        params.get("hub.mode") == "subscribe"
        and params.get("hub.verify_token") == settings.fb_verify_token
    ):
        return params.get("hub.challenge", "")
    raise HTTPException(status_code=403, detail="Verification failed")


async def _is_chatbot_enabled() -> bool:
    r = await get_redis()
    val = await r.get(_CHATBOT_STATE_KEY)
    return val != "off"


@router.post("/webhook", status_code=200)
async def receive_message(request: Request):
    settings = get_settings()
    logger.info("Melo webhook POST received")

    if not settings.fb_page_access_token or not settings.groq_api_key:
        logger.warning("Melo chatbot not configured — missing env vars")
        return {"status": "not configured"}

    body = await request.json()

    if body.get("object") != "page":
        return {"status": "ignored"}

    for entry in body.get("entry", []):
        for event in entry.get("messaging", []):
            sender_id = event.get("sender", {}).get("id")
            message = event.get("message", {})
            text = message.get("text", "").strip()

            if not text or message.get("is_echo"):
                continue

            lower = text.lower()

            # Toggle commands
            if lower == f"on {_TOGGLE_PASSWORD}":
                r = await get_redis()
                await r.set(_CHATBOT_STATE_KEY, "on")
                logger.info("Chatbot ENABLED by sender=%s", sender_id)
                await send_fb_message(sender_id, "✅ The chatbot has been turned ON.", settings.fb_page_access_token)
                continue

            if lower == f"off {_TOGGLE_PASSWORD}":
                r = await get_redis()
                await r.set(_CHATBOT_STATE_KEY, "off")
                logger.info("Chatbot DISABLED by sender=%s", sender_id)
                await send_fb_message(sender_id, "⏸️ The chatbot has been turned OFF.", settings.fb_page_access_token)
                continue

            # Skip if chatbot is disabled
            if not await _is_chatbot_enabled():
                logger.info("Chatbot disabled, skipping message from sender=%s", sender_id)
                continue

            try:
                reply = await get_ai_reply(text, settings.groq_api_key)
                await send_fb_message(sender_id, reply, settings.fb_page_access_token)
            except Exception:
                logger.exception("Error handling message from %s", sender_id)

    return {"status": "ok"}

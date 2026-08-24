# Flutter engine and plugin keep rules are generated automatically; add only
# app-specific exclusions here.

# Keep cryptography-related classes referenced reflectively by pointycastle.
-keep class org.bouncycastle.** { *; }
-dontwarn org.bouncycastle.**

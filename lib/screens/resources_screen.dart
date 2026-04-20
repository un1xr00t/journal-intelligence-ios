// lib/screens/resources_screen.dart
//
// Personalized support resources — ranked by AI from journal patterns.
// Pushed from Settings → SUPPORT → Resources.
// Routes: GET /api/resources · POST /api/resources/generate

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

// ── Static resource library ───────────────────────────────────────────────────
// AI ranks + contextualises these. Phone numbers / URLs are curated here only.

class _ResourceItem {
  final String name;
  final String description;
  final String type; // technique | app | hotline | service | directory | organization | community | resource | tool
  final String? url;
  final String? phone;
  const _ResourceItem({
    required this.name,
    required this.description,
    required this.type,
    this.url,
    this.phone,
  });
}

class _ResourceCategory {
  final String id;
  final String title;
  final String emoji;
  final Color color;
  final String defaultContext;
  final List<_ResourceItem> resources;
  const _ResourceCategory({
    required this.id,
    required this.title,
    required this.emoji,
    required this.color,
    required this.defaultContext,
    required this.resources,
  });
}

const _kResourceLibrary = <String, _ResourceCategory>{
  'grounding': _ResourceCategory(
    id: 'grounding',
    title: 'Grounding & Calming',
    emoji: '🌿',
    color: Color(0xFF10b981),
    defaultContext: 'Simple, accessible tools for when you need to slow down and feel steady.',
    resources: [
      _ResourceItem(name: 'Box Breathing', description: '4-count inhale, hold, exhale, hold — repeat 4 times to calm the nervous system', type: 'technique'),
      _ResourceItem(name: '5-4-3-2-1 Grounding', description: 'Name 5 things you see, 4 you hear, 3 you can touch, 2 you smell, 1 you taste', type: 'technique'),
      _ResourceItem(name: 'Progressive Muscle Relaxation', description: 'Tense and release each muscle group from toes to head — 15 to 20 minutes', type: 'technique'),
      _ResourceItem(name: 'Physiological Sigh', description: 'Double inhale through nose, then long slow exhale through mouth — fastest known way to lower stress', type: 'technique'),
      _ResourceItem(name: 'Body Scan Meditation', description: 'Lie down, close eyes, slowly move attention from feet to crown — notice without judgment', type: 'technique'),
      _ResourceItem(name: 'Safe Place Visualization', description: 'Close your eyes and vividly imagine a place where you feel completely safe and calm', type: 'technique'),
      _ResourceItem(name: 'Headspace', description: 'Guided meditation, breathing, and sleep tools — free trial available', type: 'app', url: 'https://headspace.com'),
      _ResourceItem(name: 'Calm', description: 'Sleep stories, meditations, and breathing exercises for daily stress', type: 'app', url: 'https://calm.com'),
      _ResourceItem(name: 'Insight Timer', description: 'Free library of 150,000+ guided meditations in dozens of languages', type: 'app', url: 'https://insighttimer.com'),
      _ResourceItem(name: 'UCLA Mindful', description: 'Free app with guided meditations in English and Spanish from UCLA', type: 'app', url: 'https://www.uclahealth.org/programs/mindful'),
      _ResourceItem(name: 'PTSD Coach', description: 'VA-developed grounding and coping tools — free, no account needed', type: 'app', url: 'https://www.ptsd.va.gov/appvid/mobile/ptsdcoach_app.asp'),
      _ResourceItem(name: 'Balance', description: 'Personalized daily meditation plans — free for the first year', type: 'app', url: 'https://www.balanceapp.com'),
    ],
  ),
  'emotional_support': _ResourceCategory(
    id: 'emotional_support',
    title: 'Emotional Support & Therapy',
    emoji: '💬',
    color: Color(0xFF8b5cf6),
    defaultContext: "Talking to someone trained to listen can help you process what you're carrying.",
    resources: [
      _ResourceItem(name: 'BetterHelp', description: 'Online therapy — text, video, or phone sessions with licensed therapists', type: 'service', url: 'https://betterhelp.com'),
      _ResourceItem(name: 'Talkspace', description: 'Online therapy and psychiatry — covered by many major insurance plans', type: 'service', url: 'https://talkspace.com'),
      _ResourceItem(name: 'Open Path Collective', description: 'Affordable in-person and online therapy, \$30–\$80 per session', type: 'service', url: 'https://openpathcollective.org'),
      _ResourceItem(name: 'Psychology Today', description: 'Find local therapists filterable by specialty, insurance, and identity', type: 'directory', url: 'https://www.psychologytoday.com/us/therapists'),
      _ResourceItem(name: 'Alma', description: 'Insurance-covered therapist network with diverse providers nationwide', type: 'directory', url: 'https://helloalma.com'),
      _ResourceItem(name: 'TherapyDen', description: 'Find LGBTQ+-affirming, BIPOC, and culturally competent therapists', type: 'directory', url: 'https://therapyden.com'),
      _ResourceItem(name: 'SAMHSA Helpline', description: 'Free, confidential mental health and substance use referrals, 24/7', type: 'hotline', phone: '1-800-662-4357'),
      _ResourceItem(name: 'NAMI Helpline', description: 'Support, info, and referrals — Mon–Fri, 10am–10pm ET', type: 'hotline', phone: '1-800-950-6264'),
      _ResourceItem(name: '7 Cups', description: 'Free anonymous chat with trained volunteer listeners — 24/7', type: 'service', url: 'https://7cups.com'),
      _ResourceItem(name: 'Warmline Directory', description: 'Find your state warmline — someone to talk to before crisis hits', type: 'hotline', url: 'https://warmline.org'),
    ],
  ),
  'mental_health': _ResourceCategory(
    id: 'mental_health',
    title: 'Mental Health & Wellbeing',
    emoji: '🧠',
    color: Color(0xFF6366f1),
    defaultContext: 'Resources for understanding and supporting your mental wellbeing over time.',
    resources: [
      _ResourceItem(name: 'NAMI', description: 'National Alliance on Mental Illness — education, helpline, advocacy, and local support groups', type: 'organization', url: 'https://nami.org'),
      _ResourceItem(name: 'Mental Health America', description: 'Free screening tools, resources, and local affiliate support across the US', type: 'organization', url: 'https://mhanational.org'),
      _ResourceItem(name: 'NIMH', description: 'National Institute of Mental Health — research-backed info on every condition', type: 'resource', url: 'https://www.nimh.nih.gov'),
      _ResourceItem(name: 'SAMHSA', description: 'Federal mental health and addiction resources — nationwide treatment locator', type: 'organization', url: 'https://www.samhsa.gov'),
      _ResourceItem(name: 'AFSP', description: 'American Foundation for Suicide Prevention — resources, research, survivor support', type: 'organization', url: 'https://afsp.org'),
      _ResourceItem(name: 'DBSA', description: 'Depression and Bipolar Support Alliance — free online and in-person peer groups', type: 'community', url: 'https://www.dbsalliance.org'),
      _ResourceItem(name: 'Sanvello', description: 'CBT-based app for anxiety, depression, and stress — free tier available', type: 'app', url: 'https://sanvello.com'),
      _ResourceItem(name: 'Woebot', description: 'AI-powered CBT mental health support chatbot', type: 'app', url: 'https://woebothealth.com'),
      _ResourceItem(name: 'Wysa', description: 'AI mental health companion with evidence-based tools and optional human coaching', type: 'app', url: 'https://wysa.io'),
      _ResourceItem(name: 'Daylio', description: 'Micro mood journal and habit tracker — identify your emotional patterns over time', type: 'app', url: 'https://daylio.net'),
    ],
  ),
  'relationship': _ResourceCategory(
    id: 'relationship',
    title: 'Relationship & Family Support',
    emoji: '🤝',
    color: Color(0xFFec4899),
    defaultContext: 'Support for navigating difficult relationships, conflict, and family dynamics.',
    resources: [
      _ResourceItem(name: 'National DV Hotline', description: '24/7 domestic violence support — call or text START to 88788', type: 'hotline', phone: '1-800-799-7233', url: 'https://thehotline.org'),
      _ResourceItem(name: 'Love Is Respect', description: 'Relationship abuse resources — call or text LOVEIS to 22522', type: 'hotline', phone: '1-866-331-9474', url: 'https://loveisrespect.org'),
      _ResourceItem(name: 'WomensLaw.org', description: 'State-by-state legal information for abuse survivors — confidential live chat', type: 'resource', url: 'https://womenslaw.org'),
      _ResourceItem(name: 'Safe Horizon', description: 'Crisis support for victims of violence and abuse', type: 'service', phone: '1-800-621-4673', url: 'https://safehorizon.org'),
      _ResourceItem(name: 'DomesticShelters.org', description: 'Find local domestic violence shelters and services by zip code', type: 'directory', url: 'https://www.domesticshelters.org'),
      _ResourceItem(name: 'Futures Without Violence', description: 'Resources for survivors and anyone supporting a person through abuse', type: 'organization', url: 'https://www.futureswithoutviolence.org'),
      _ResourceItem(name: 'Relationship Hero', description: 'Online relationship coaches available 24/7 for any situation', type: 'service', url: 'https://relationshiphero.com'),
      _ResourceItem(name: 'Codependents Anonymous', description: 'Free 12-step support groups for unhealthy relationship patterns', type: 'community', url: 'https://coda.org'),
      _ResourceItem(name: 'Al-Anon', description: "Peer support for families and friends affected by someone else's drinking", type: 'community', url: 'https://al-anon.org'),
    ],
  ),
  'parenting': _ResourceCategory(
    id: 'parenting',
    title: 'Parenting & Co-Parenting',
    emoji: '🌻',
    color: Color(0xFFf59e0b),
    defaultContext: 'Support for parents navigating stress, single parenting, or co-parenting challenges.',
    resources: [
      _ResourceItem(name: 'Childhelp Hotline', description: 'Support for parents under stress and children in need', type: 'hotline', phone: '1-800-422-4453'),
      _ResourceItem(name: 'Boys Town National Hotline', description: '24/7 crisis and parenting support for parents and teens', type: 'hotline', phone: '1-800-448-3000'),
      _ResourceItem(name: 'Parents Helpline', description: 'Emotional support and local referrals for struggling parents', type: 'hotline', phone: '1-855-427-2736'),
      _ResourceItem(name: 'Postpartum Support International', description: 'Postpartum depression and anxiety support', type: 'hotline', phone: '1-800-944-4773', url: 'https://postpartum.net'),
      _ResourceItem(name: 'Child Mind Institute', description: 'Expert guidance on child and teen mental health — free articles and guides by age', type: 'resource', url: 'https://childmind.org'),
      _ResourceItem(name: 'Zero to Three', description: 'Parenting resources and developmental support for children ages 0–3', type: 'resource', url: 'https://zerotothree.org'),
      _ResourceItem(name: 'Our Family Wizard', description: 'Co-parenting communication and scheduling — court-accepted documentation', type: 'tool', url: 'https://ourfamilywizard.com'),
      _ResourceItem(name: 'TalkingParents', description: 'Documented co-parenting messaging — timestamped records for legal use', type: 'tool', url: 'https://talkingparents.com'),
    ],
  ),
  'legal': _ResourceCategory(
    id: 'legal',
    title: 'Legal Aid & Rights',
    emoji: '⚖️',
    color: Color(0xFF64748b),
    defaultContext: 'Understanding your rights and finding help navigating legal processes.',
    resources: [
      _ResourceItem(name: 'LawHelp.org', description: 'Free legal information and attorney referrals by state', type: 'resource', url: 'https://lawhelp.org'),
      _ResourceItem(name: 'Legal Services Corporation', description: 'Find free civil legal aid programs in your area', type: 'directory', url: 'https://www.lsc.gov/about-lsc/what-legal-aid/get-legal-help'),
      _ResourceItem(name: 'ABA Free Legal Answers', description: 'Submit civil legal questions and get answers from volunteer attorneys — free', type: 'service', url: 'https://abafreelegalanswers.org'),
      _ResourceItem(name: 'Avvo', description: 'Free legal Q&A community and attorney directory with ratings', type: 'directory', url: 'https://avvo.com'),
      _ResourceItem(name: 'Nolo', description: 'Plain-English legal guides, self-help forms, and attorney finder', type: 'resource', url: 'https://nolo.com'),
      _ResourceItem(name: 'Law Help Interactive', description: 'Create free court-ready legal documents for your situation', type: 'tool', url: 'https://lawhelpinteractive.org'),
      _ResourceItem(name: 'WomensLaw Legal Help', description: 'Free legal information for abuse survivors — email hotline available', type: 'service', url: 'https://womenslaw.org/find-help/i-need-help/email-hotline'),
      _ResourceItem(name: 'Victims of Crime', description: 'Resources and compensation info for crime victims — helpline: 1-855-4-VICTIM', type: 'resource', url: 'https://victimsofcrime.org'),
    ],
  ),
  'housing': _ResourceCategory(
    id: 'housing',
    title: 'Housing & Practical Needs',
    emoji: '🏠',
    color: Color(0xFF0ea5e9),
    defaultContext: 'Help finding stable housing and practical support in difficult times.',
    resources: [
      _ResourceItem(name: '211 Helpline', description: 'Dial 2-1-1 — connects to local housing, food, utility, and emergency financial help', type: 'hotline', phone: '211', url: 'https://211.org'),
      _ResourceItem(name: 'National Homelessness Hotline', description: 'Connects to local emergency shelters and housing services', type: 'hotline', phone: '1-800-466-3537'),
      _ResourceItem(name: 'HUD Housing Assistance', description: 'Federal rental and housing voucher programs — find your local HUD office', type: 'resource', url: 'https://www.hud.gov/topics/rental_assistance'),
      _ResourceItem(name: 'NLIHC Resource Finder', description: 'Find emergency rental assistance programs by state and county', type: 'directory', url: 'https://nlihc.org/find-assistance'),
      _ResourceItem(name: 'Benefits.gov', description: 'Search all federal and state benefit programs you may qualify for', type: 'resource', url: 'https://benefits.gov'),
      _ResourceItem(name: 'Salvation Army', description: 'Emergency shelter, food assistance, and utility help nationwide', type: 'service', url: 'https://salvationarmyusa.org'),
      _ResourceItem(name: 'YWCA Emergency Shelter', description: 'Emergency and transitional housing for women and families fleeing abuse', type: 'service', url: 'https://www.ywca.org/what-we-do/housing-shelters'),
      _ResourceItem(name: 'Feeding America', description: 'Find your nearest food bank — no paperwork required at most locations', type: 'directory', url: 'https://feedingamerica.org/find-your-local-foodbank'),
      _ResourceItem(name: 'SNAP Benefits', description: 'Federal food assistance — check eligibility and apply online in minutes', type: 'resource', url: 'https://www.fns.usda.gov/snap'),
    ],
  ),
  'burnout': _ResourceCategory(
    id: 'burnout',
    title: 'Burnout & Work Stress',
    emoji: '🔋',
    color: Color(0xFFf97316),
    defaultContext: 'When exhaustion runs deep, these tools can help you reclaim your energy.',
    resources: [
      _ResourceItem(name: 'Employee Assistance Program (EAP)', description: 'Check with HR — most employers offer 3 to 8 free confidential counseling sessions', type: 'resource'),
      _ResourceItem(name: 'OSHA Workers Rights', description: 'File a complaint about unsafe or hostile workplace conditions — anonymously if needed', type: 'resource', url: 'https://www.osha.gov/workers/file-complaint'),
      _ResourceItem(name: 'National Labor Relations Board', description: 'Know your workplace rights and file unfair labor practice charges', type: 'resource', url: 'https://nlrb.gov'),
      _ResourceItem(name: 'Headspace for Work', description: 'Mindfulness and burnout recovery tools designed for the workplace', type: 'app', url: 'https://headspace.com/work'),
      _ResourceItem(name: 'Balance', description: 'Personalized daily meditation — free for the first year', type: 'app', url: 'https://www.balanceapp.com'),
      _ResourceItem(name: 'Happify', description: 'Science-based activities and games to reduce stress and build resilience', type: 'app', url: 'https://happify.com'),
      _ResourceItem(name: 'Burnout Index', description: 'Free anonymous burnout assessment — measure your current risk level', type: 'tool', url: 'https://burnoutindex.org'),
    ],
  ),
  'grief': _ResourceCategory(
    id: 'grief',
    title: 'Grief & Loss',
    emoji: '🕊️',
    color: Color(0xFF94a3b8),
    defaultContext: 'Support for navigating grief, loss, and the feelings that come with major endings.',
    resources: [
      _ResourceItem(name: 'GriefShare', description: 'Find local and online grief support groups by zip code', type: 'community', url: 'https://griefshare.org'),
      _ResourceItem(name: "What's Your Grief", description: 'Articles, tools, and community for grief of every kind', type: 'resource', url: 'https://whatsyourgrief.com'),
      _ResourceItem(name: 'The Dougy Center', description: 'Grief support for children, teens, young adults, and families', type: 'organization', url: 'https://www.dougy.org'),
      _ResourceItem(name: 'The Compassionate Friends', description: 'Support for families grieving the death of a child — chapters nationwide', type: 'community', url: 'https://www.compassionatefriends.org'),
      _ResourceItem(name: 'Modern Loss', description: 'Candid essays, resources, and community about navigating real grief', type: 'resource', url: 'https://modernloss.com'),
      _ResourceItem(name: 'Alliance of Hope', description: "Online support community for loss survivors after a loved one's suicide", type: 'community', url: 'https://allianceofhope.org'),
      _ResourceItem(name: 'Option B', description: 'Resilience tools and community for grief, loss, and adversity of all kinds', type: 'resource', url: 'https://optionb.org'),
    ],
  ),
  'community': _ResourceCategory(
    id: 'community',
    title: 'Connection & Community',
    emoji: '🌱',
    color: Color(0xFF34d399),
    defaultContext: "You don't have to carry this alone — finding connection can make a real difference.",
    resources: [
      _ResourceItem(name: '7 Cups', description: 'Free anonymous chat with trained volunteer listeners — 24/7', type: 'service', url: 'https://7cups.com'),
      _ResourceItem(name: 'Meetup', description: 'Find local groups built around shared interests and experiences', type: 'community', url: 'https://meetup.com'),
      _ResourceItem(name: 'SMART Recovery', description: 'Free science-based support groups for any behavioral challenge', type: 'community', url: 'https://smartrecovery.org'),
      _ResourceItem(name: 'DBSA Online Support Groups', description: 'Free online peer support groups for depression and bipolar disorder', type: 'community', url: 'https://www.dbsalliance.org/support/chapters-and-support-groups/online-support-groups'),
      _ResourceItem(name: 'Warmline Directory', description: 'Find your state warmline — peer support before you reach crisis', type: 'hotline', url: 'https://warmline.org'),
      _ResourceItem(name: 'NAMI Connection', description: 'Free weekly peer-led support groups for adults with mental illness', type: 'community', url: 'https://nami.org/Support-Education/Support-Groups/NAMI-Connection'),
      _ResourceItem(name: 'Emotions Anonymous', description: '12-step program for emotional health — in-person and virtual meetings', type: 'community', url: 'https://emotionsanonymous.org'),
    ],
  ),
  'trauma': _ResourceCategory(
    id: 'trauma',
    title: 'Trauma & PTSD',
    emoji: '🛡️',
    color: Color(0xFFa78bfa),
    defaultContext: "Trauma shapes how we feel in ways that aren't always obvious — specialized support can make a real difference.",
    resources: [
      _ResourceItem(name: 'RAINN', description: 'Sexual assault support — call 1-800-656-HOPE (4673) or chat online, 24/7', type: 'hotline', phone: '1-800-656-4673', url: 'https://rainn.org'),
      _ResourceItem(name: 'PTSD Coach', description: 'VA-developed app for PTSD symptoms — grounding, coping tools, and psychoeducation', type: 'app', url: 'https://www.ptsd.va.gov/appvid/mobile/ptsdcoach_app.asp'),
      _ResourceItem(name: 'National Child Traumatic Stress Network', description: 'Trauma resources for children, teens, and families — find specialized treatment', type: 'organization', url: 'https://nctsn.org'),
      _ResourceItem(name: 'EMDR International Association', description: 'Find a certified EMDR therapist for trauma processing and reprocessing', type: 'directory', url: 'https://emdria.org'),
      _ResourceItem(name: 'SAMHSA Trauma Resources', description: 'Trauma-informed care resources, treatment locator, and educational guides', type: 'resource', url: 'https://www.samhsa.gov/trauma-violence'),
      _ResourceItem(name: 'Self-Compassion.org', description: 'Free guided meditations and exercises for self-compassion and healing', type: 'resource', url: 'https://self-compassion.org'),
      _ResourceItem(name: 'National Center for PTSD', description: 'VA-backed research, tools, and treatment information for PTSD', type: 'resource', url: 'https://www.ptsd.va.gov'),
    ],
  ),
  'addiction': _ResourceCategory(
    id: 'addiction',
    title: 'Addiction & Recovery',
    emoji: '🌊',
    color: Color(0xFF06b6d4),
    defaultContext: "Recovery is nonlinear and hard — but real support exists, and you don't have to do it alone.",
    resources: [
      _ResourceItem(name: 'SAMHSA National Helpline', description: 'Free, confidential treatment referrals for substance use, 24/7, English and Spanish', type: 'hotline', phone: '1-800-662-4357'),
      _ResourceItem(name: 'AA — Alcoholics Anonymous', description: 'Find local and online meetings for alcohol recovery — worldwide 12-step community', type: 'community', url: 'https://aa.org'),
      _ResourceItem(name: 'NA — Narcotics Anonymous', description: 'Find meetings for drug addiction recovery — supportive worldwide community', type: 'community', url: 'https://na.org'),
      _ResourceItem(name: 'SMART Recovery', description: 'Science-based alternative to 12-step — free in-person and online meetings', type: 'community', url: 'https://smartrecovery.org'),
      _ResourceItem(name: 'In The Rooms', description: 'Online recovery meetings for 29 fellowships — available any time of day', type: 'community', url: 'https://intherooms.com'),
      _ResourceItem(name: 'Hazelden Betty Ford', description: 'Addiction treatment, recovery resources, and a 24/7 helpline', type: 'service', url: 'https://hazeldenbettyford.org'),
      _ResourceItem(name: 'NIDA', description: 'National Institute on Drug Abuse — research-based info on addiction and treatment options', type: 'resource', url: 'https://nida.nih.gov'),
      _ResourceItem(name: 'Nar-Anon', description: 'Support groups for family members and friends of people struggling with addiction', type: 'community', url: 'https://nar-anon.org'),
    ],
  ),
  'financial': _ResourceCategory(
    id: 'financial',
    title: 'Financial Hardship',
    emoji: '💰',
    color: Color(0xFF84cc16),
    defaultContext: 'Financial stress is real and grinding — practical help and expert guidance are available.',
    resources: [
      _ResourceItem(name: '211 Helpline', description: 'Dial 2-1-1 — emergency financial, food, and utility help in your area', type: 'hotline', phone: '211', url: 'https://211.org'),
      _ResourceItem(name: 'NFCC Credit Counseling', description: 'National Foundation for Credit Counseling — free and low-cost debt and budget help', type: 'service', url: 'https://nfcc.org'),
      _ResourceItem(name: 'Consumer Financial Protection Bureau', description: 'Know your financial rights, submit complaints, and use free financial tools', type: 'resource', url: 'https://consumerfinance.gov'),
      _ResourceItem(name: 'Benefits.gov', description: 'Find all federal and state benefit programs you may qualify for', type: 'resource', url: 'https://benefits.gov'),
      _ResourceItem(name: 'SNAP Benefits', description: 'Federal food assistance — check eligibility and apply online in minutes', type: 'resource', url: 'https://www.fns.usda.gov/snap'),
      _ResourceItem(name: 'Modest Needs', description: 'Small emergency grants for working people facing unexpected financial shortfalls', type: 'service', url: 'https://modestneeds.org'),
      _ResourceItem(name: 'Feeding America', description: 'Find your nearest food bank — no income documentation required at most locations', type: 'directory', url: 'https://feedingamerica.org/find-your-local-foodbank'),
      _ResourceItem(name: 'GreenPath Financial Wellness', description: 'Nonprofit credit counseling and debt management', type: 'service', phone: '1-877-337-3399', url: 'https://greenpath.com'),
    ],
  ),
  'lgbtq': _ResourceCategory(
    id: 'lgbtq',
    title: 'LGBTQ+ Support',
    emoji: '🏳️‍🌈',
    color: Color(0xFFf472b6),
    defaultContext: 'Affirming support that understands your experience — for every part of the LGBTQ+ community.',
    resources: [
      _ResourceItem(name: 'The Trevor Project', description: 'Crisis support for LGBTQ+ youth — call or text START to 678-678, 24/7', type: 'hotline', phone: '1-866-488-7386', url: 'https://thetrevorproject.org'),
      _ResourceItem(name: 'Trans Lifeline', description: 'Peer support hotline run by trans people for trans people', type: 'hotline', phone: '877-565-8860', url: 'https://translifeline.org'),
      _ResourceItem(name: 'PFLAG', description: 'Support for LGBTQ+ people, their families, and allies — find local chapters', type: 'community', url: 'https://pflag.org'),
      _ResourceItem(name: 'Lambda Legal', description: 'Legal protection for LGBTQ+ civil rights — helpline for legal questions', type: 'resource', url: 'https://lambdalegal.org'),
      _ResourceItem(name: 'National Center for Transgender Equality', description: 'Policy advocacy and practical resources for transgender rights', type: 'organization', url: 'https://transequality.org'),
      _ResourceItem(name: 'It Gets Better Project', description: 'Stories and resources affirming LGBTQ+ youth — community and global mentorship', type: 'resource', url: 'https://itgetsbetter.org'),
      _ResourceItem(name: 'SAGE', description: 'Services and advocacy for LGBTQ+ elders — National Hotline: 1-877-360-5428', type: 'hotline', phone: '1-877-360-5428', url: 'https://sageusa.org'),
      _ResourceItem(name: 'TherapyDen', description: 'Find LGBTQ+-affirming therapists who understand your lived experience', type: 'directory', url: 'https://therapyden.com'),
    ],
  ),
  'veterans': _ResourceCategory(
    id: 'veterans',
    title: 'Veterans & Military',
    emoji: '🎖️',
    color: Color(0xFF78716c),
    defaultContext: 'Specialized mental health and practical support for veterans and active-duty military.',
    resources: [
      _ResourceItem(name: 'Veterans Crisis Line', description: 'Call 988 then press 1, or text 838255 — free, confidential, 24/7 for vets and family', type: 'hotline', phone: '988', url: 'https://veteranscrisisline.net'),
      _ResourceItem(name: 'VA Mental Health Services', description: 'PTSD, depression, MST, and addiction treatment — find a VA facility near you', type: 'service', url: 'https://mentalhealth.va.gov'),
      _ResourceItem(name: 'Give an Hour', description: 'Free mental health care for post-9/11 veterans, service members, and families', type: 'service', url: 'https://giveanhour.org'),
      _ResourceItem(name: 'Headstrong', description: 'Free mental health treatment for post-9/11 veterans — no paperwork, no copays', type: 'service', url: 'https://goheadstrong.org'),
      _ResourceItem(name: 'Vets4Warriors', description: '24/7 peer support by veterans for veterans', type: 'hotline', phone: '1-855-838-8255', url: 'https://vets4warriors.com'),
      _ResourceItem(name: 'Wounded Warrior Project', description: 'Programs for physical, mental, and financial wellness for injured veterans', type: 'organization', url: 'https://woundedwarriorproject.org'),
      _ResourceItem(name: 'NAMI Veterans', description: 'Mental health resources and peer support specifically tailored to veterans', type: 'resource', url: 'https://www.nami.org/Your-Journey/Veterans-Active-Duty'),
    ],
  ),
  'chronic_illness': _ResourceCategory(
    id: 'chronic_illness',
    title: 'Chronic Illness & Disability',
    emoji: '🌡️',
    color: Color(0xFF22d3ee),
    defaultContext: 'Living with chronic illness or disability is exhausting — you deserve real support for that reality.',
    resources: [
      _ResourceItem(name: 'Patient Advocate Foundation', description: 'Free case management for chronic illness patients — insurance, billing, and debt help', type: 'service', url: 'https://patientadvocate.org'),
      _ResourceItem(name: 'HealthWell Foundation', description: 'Grants for out-of-pocket healthcare costs for underinsured patients', type: 'service', url: 'https://healthwellfoundation.org'),
      _ResourceItem(name: 'American Chronic Pain Association', description: 'Peer support groups and self-management tools for chronic pain', type: 'community', url: 'https://theacpa.org'),
      _ResourceItem(name: 'NORD', description: 'National Organization for Rare Disorders — patient assistance and disease-specific resources', type: 'organization', url: 'https://rarediseases.org'),
      _ResourceItem(name: 'Social Security Disability', description: 'Apply for SSDI or SSI if your condition prevents full-time work', type: 'resource', url: 'https://ssa.gov/disability'),
      _ResourceItem(name: 'Disability Rights Advocates', description: 'Free legal representation for disability discrimination cases', type: 'service', url: 'https://dralegal.org'),
      _ResourceItem(name: 'Caregiver Action Network', description: 'Support and education for family caregivers of people with chronic illness', type: 'resource', url: 'https://caregiveraction.org'),
    ],
  ),
  'crisis': _ResourceCategory(
    id: 'crisis',
    title: 'Crisis & Immediate Safety',
    emoji: '🆘',
    color: Color(0xFFf59e0b),
    defaultContext: "If you're struggling right now, these resources are here for you — free, confidential, and always available.",
    resources: [
      _ResourceItem(name: '988 Suicide & Crisis Lifeline', description: 'Call or text 988 — free, confidential, 24/7 for anyone in distress', type: 'hotline', phone: '988'),
      _ResourceItem(name: 'Crisis Text Line', description: 'Text HOME to 741741 — free, confidential text-based crisis support, 24/7', type: 'hotline'),
      _ResourceItem(name: 'Veterans Crisis Line', description: 'Call 988 then press 1, or text 838255 — for veterans and their families, 24/7', type: 'hotline', phone: '988', url: 'https://veteranscrisisline.net'),
      _ResourceItem(name: 'Trevor Project', description: 'Call or text START to 678-678 — LGBTQ+ youth crisis support, 24/7', type: 'hotline', phone: '1-866-488-7386', url: 'https://thetrevorproject.org'),
      _ResourceItem(name: 'Trans Lifeline', description: 'Peer crisis support run by trans people for trans people', type: 'hotline', phone: '877-565-8860', url: 'https://translifeline.org'),
      _ResourceItem(name: 'RAINN', description: 'Sexual assault support — call or chat online, 24/7', type: 'hotline', phone: '1-800-656-4673', url: 'https://rainn.org'),
      _ResourceItem(name: 'National DV Hotline', description: 'Call or text START to 88788 — domestic violence support, 24/7', type: 'hotline', phone: '1-800-799-7233', url: 'https://thehotline.org'),
      _ResourceItem(name: 'Emergency Services', description: 'Call 911 if you are in immediate physical danger', type: 'hotline', phone: '911'),
    ],
  ),
};

// ── Screen ────────────────────────────────────────────────────────────────────

class ResourcesScreen extends StatefulWidget {
  const ResourcesScreen({super.key});

  @override
  State<ResourcesScreen> createState() => _ResourcesScreenState();
}

class _ResourcesScreenState extends State<ResourcesScreen> {
  final _api = ApiService();

  bool _loading     = true;
  bool _generating  = false;
  String? _error;

  Map<String, dynamic>? _profile;
  String? _generatedAt;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await _api.getResources();
      if (mounted) setState(() {
        final hasProfile = data?['has_profile'] == true;
        _profile     = hasProfile ? data!['profile'] as Map<String, dynamic>? : null;
        _generatedAt = data?['generated_at'] as String?;
        _loading     = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error   = 'Could not load resources — check your connection.';
        _loading = false;
      });
    }
  }

  Future<void> _generate({bool force = false}) async {
    if (_generating) return;
    setState(() { _generating = true; _error = null; });
    try {
      final data = await _api.generateResources(force: force);
      if (mounted) setState(() {
        _profile     = data['profile'] as Map<String, dynamic>?;
        _generatedAt = data['generated_at'] as String?;
        _generating  = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error      = 'Could not generate recommendations — try again.';
        _generating = false;
      });
    }
  }

  bool get _isStale {
    if (_generatedAt == null) return false;
    final generated = DateTime.tryParse(_generatedAt!);
    if (generated == null) return false;
    return DateTime.now().difference(generated).inDays > 7;
  }

  String _fmtDate(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final ranked       = (_profile?['ranked_categories'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final surfaceCrisis = _profile?['surface_crisis'] == true;
    final crisisEntry  = surfaceCrisis ? ranked.where((c) => c['id'] == 'crisis').firstOrNull : null;
    final mainEntries  = crisisEntry != null ? ranked.where((c) => c['id'] != 'crisis').toList() : ranked;

    return CupertinoPageScaffold(
      backgroundColor: JournalColors.bgBase,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: JournalColors.bgBase.withOpacity(0.9),
        border: const Border(bottom: BorderSide(color: JournalColors.border, width: 0.5)),
        middle: const Text('Resources',
            style: TextStyle(color: JournalColors.textPrimary, fontWeight: FontWeight.w600)),
        trailing: _profile != null
            ? GestureDetector(
                onTap: _generating ? null : () => _generate(force: true),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _generating
                        ? JournalColors.accent.withOpacity(0.06)
                        : JournalColors.accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: JournalColors.accent.withOpacity(0.30),
                    ),
                  ),
                  child: _generating
                      ? const CupertinoActivityIndicator(radius: 7)
                      : const Text('Refresh',
                          style: TextStyle(
                            color: JournalColors.accent,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          )),
                ),
              )
            : null,
      ),
      child: SafeArea(
        child: _loading
            ? const Center(child: CupertinoActivityIndicator())
            : _buildBody(ranked, crisisEntry, mainEntries),
      ),
    );
  }

  Widget _buildBody(
    List<Map<String, dynamic>> ranked,
    Map<String, dynamic>? crisisEntry,
    List<Map<String, dynamic>> mainEntries,
  ) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        // Error banner
        if (_error != null) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.withOpacity(0.25)),
            ),
            child: Text(_error!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
          ),
        ],

        // ── No profile yet ──────────────────────────────────────────
        if (_profile == null && _error == null) ...[
          const SizedBox(height: 32),
          const Text('Support Resources',
              style: TextStyle(
                  color: JournalColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text(
            'Based on what you\'ve shared, we\'ll surface the support resources most relevant to your situation.',
            style: TextStyle(color: JournalColors.textSecondary, fontSize: 14, height: 1.6),
          ),
          const SizedBox(height: 28),
          GestureDetector(
            onTap: _generating ? null : () => _generate(force: false),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [JournalColors.accent, Color(0xFF7c3aed)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: _generating
                  ? const CupertinoActivityIndicator(color: Colors.white, radius: 10)
                  : const Text('Show My Resources',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Uses your journal patterns and onboarding context. Nothing is shared externally.',
            textAlign: TextAlign.center,
            style: TextStyle(color: JournalColors.textMuted, fontSize: 11, height: 1.6),
          ),
          const SizedBox(height: 40),
        ],

        // ── Profile loaded ──────────────────────────────────────────
        if (_profile != null) ...[
          // Stale / date badge
          if (_generatedAt != null) ...[
            Row(children: [
              if (_isStale) ...[
                const Icon(CupertinoIcons.exclamationmark_circle,
                    color: Color(0xFFf59e0b), size: 13),
                const SizedBox(width: 4),
              ],
              Text(
                '${_isStale ? 'Outdated — ' : ''}Updated ${_fmtDate(_generatedAt)}',
                style: TextStyle(
                  color: _isStale ? const Color(0xFFf59e0b) : JournalColors.textMuted,
                  fontSize: 11,
                ),
              ),
            ]),
            const SizedBox(height: 12),
          ],

          // Personalized intro
          if ((_profile!['intro'] as String? ?? '').trim().isNotEmpty) ...[
            _IntroCard(text: (_profile!['intro'] as String).trim()),
            const SizedBox(height: 20),
          ],

          // Crisis — pinned top when signals warrant it
          if (crisisEntry != null) ...[
            _SectionLabel('IF YOU NEED SUPPORT RIGHT NOW'),
            const SizedBox(height: 8),
            _CategoryCard(
              categoryId: crisisEntry['id'] as String,
              context: crisisEntry['context'] as String? ?? '',
              isCrisis: true,
            ),
            const SizedBox(height: 20),
          ],

          // Main ranked categories
          if (mainEntries.isNotEmpty) ...[
            _SectionLabel('RESOURCES FOR YOU'),
            const SizedBox(height: 8),
            ...mainEntries.map((entry) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _CategoryCard(
                categoryId: entry['id'] as String,
                context: entry['context'] as String? ?? '',
                isCrisis: false,
              ),
            )),
          ],

          const SizedBox(height: 24),

          // Privacy footer
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.015),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: JournalColors.border, style: BorderStyle.solid),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('🔒', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'These recommendations are generated from your private journal patterns. Nothing is shared externally. Refresh as your situation changes.',
                  style: TextStyle(
                      color: JournalColors.textMuted,
                      fontSize: 11,
                      height: 1.65),
                ),
              ),
            ]),
          ),
        ],
      ],
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: JournalColors.textMuted,
      fontSize: 10,
      letterSpacing: 0.8,
      fontWeight: FontWeight.w600,
    ),
  );
}

// ── Intro card ────────────────────────────────────────────────────────────────

class _IntroCard extends StatelessWidget {
  final String text;
  const _IntroCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PERSONALIZED FOR YOU',
            style: TextStyle(
              color: JournalColors.accent,
              fontSize: 9,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: TextStyle(
              color: JournalColors.textSecondary,
              fontSize: 13,
              height: 1.7,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Category card ─────────────────────────────────────────────────────────────

class _CategoryCard extends StatefulWidget {
  final String categoryId;
  final String context;
  final bool isCrisis;
  const _CategoryCard({
    required this.categoryId,
    required this.context,
    required this.isCrisis,
  });

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cat = _kResourceLibrary[widget.categoryId];
    if (cat == null) return const SizedBox.shrink();

    final displayContext = widget.context.isNotEmpty ? widget.context : cat.defaultContext;

    return GlassCard(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header row
        Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: cat.color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(cat.emoji, style: const TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(cat.title,
                style: const TextStyle(
                    color: JournalColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
          ),
          Icon(
            _expanded ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down,
            color: JournalColors.textMuted,
            size: 14,
          ),
        ]),

        const SizedBox(height: 10),

        // AI context blurb
        Text(
          displayContext,
          style: const TextStyle(
              color: JournalColors.textSecondary, fontSize: 12, height: 1.65),
        ),

        // Expanded resource list
        if (_expanded) ...[
          const SizedBox(height: 12),
          const Divider(color: JournalColors.border, height: 1),
          const SizedBox(height: 12),
          ...cat.resources.map((r) => _ResourceRow(item: r)),
        ],
      ]),
    );
  }
}

// ── Resource row ──────────────────────────────────────────────────────────────

class _ResourceRow extends StatelessWidget {
  final _ResourceItem item;
  const _ResourceRow({required this.item});

  Color _typeColor(String type) {
    return switch (type) {
      'hotline'      => const Color(0xFFef4444),
      'app'          => const Color(0xFF6366f1),
      'service'      => const Color(0xFF8b5cf6),
      'directory'    => const Color(0xFF0ea5e9),
      'organization' => const Color(0xFF10b981),
      'community'    => const Color(0xFFec4899),
      'technique'    => const Color(0xFF10b981),
      'tool'         => const Color(0xFF0ea5e9),
      _              => JournalColors.textMuted,
    };
  }

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    showCupertinoDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => const CupertinoAlertDialog(
        title: Text('Copied'),
        content: Text('Phone number copied to clipboard.'),
      ),
    );
  }

  Future<void> _launchPhone(BuildContext context, String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _copyToClipboard(context, phone);
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasLink  = item.url != null;
    final hasPhone = item.phone != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Type dot
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: _typeColor(item.type),
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(item.name,
                    style: const TextStyle(
                        color: JournalColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
              // Type badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _typeColor(item.type).withOpacity(0.10),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  item.type.replaceAll('_', ' '),
                  style: TextStyle(
                      color: _typeColor(item.type),
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4),
                ),
              ),
            ]),
            const SizedBox(height: 3),
            Text(item.description,
                style: const TextStyle(
                    color: JournalColors.textSecondary, fontSize: 11, height: 1.5)),
            // CTA buttons
            if (hasPhone || hasLink) ...[
              const SizedBox(height: 8),
              Row(children: [
                if (hasPhone)
                  GestureDetector(
                    onTap: () => _launchPhone(context, item.phone!),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _typeColor(item.type).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _typeColor(item.type).withOpacity(0.30)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(CupertinoIcons.phone_fill,
                            color: _typeColor(item.type), size: 11),
                        const SizedBox(width: 5),
                        Text(item.phone!,
                            style: TextStyle(
                                color: _typeColor(item.type),
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                if (hasPhone && hasLink) const SizedBox(width: 8),
                if (hasLink)
                  GestureDetector(
                    onTap: () => _launchUrl(item.url!),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: JournalColors.accent.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: JournalColors.accent.withOpacity(0.25)),
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(CupertinoIcons.arrow_up_right_square,
                            color: JournalColors.accent, size: 11),
                        SizedBox(width: 5),
                        Text('Open',
                            style: TextStyle(
                                color: JournalColors.accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }
}
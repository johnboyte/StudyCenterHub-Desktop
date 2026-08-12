-- Migration 0044: Real Life House Fall 2026 Phone Menu & Main Greeting Scripts Configuration
-- Establishes current Fall 2026 scripts and 6-option caller menu structure for Real Life House

INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('GATEWAY_SYNC_API_KEY', 'SCH_SYNC_KEY_PLACEHOLDER_8f3d');

INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES (
    'PHONE_AUTOMATED_GREETER_TTS',
    'Thank you for calling Real Life House, a Christian Study Center and Hospitality House serving the Anderson University community.

We are a place for Christian life, thought, friendship, and formation, and we would love to welcome you.

For current House Hours, opening-week information, and what is happening at the House, press 1.

For Real Life on Sunday evenings, press 2.

To learn more about Real Life House, press 3.

For volunteering, internships, music and worship opportunities, and other ways to get involved, press 4.

For our location, website, and contact information, press 5.

To leave us a message, press 6.

You can also visit us anytime at RealLifeHouse dot org.

Come in. Sit down. Stay awhile.'
);

DELETE FROM ivr_menu_options;

INSERT INTO ivr_menu_options (digit, menu_option_name, script_text, action_type, action_param)
VALUES (
    '1',
    'Hours & What’s Happening',
    'Real Life House is getting ready to welcome students for the Fall 2026 semester.

On Friday, August 21, Anderson University move-in day, the House will be open during the day, and students and families are invited to drop by, look around, meet us, grab some coffee, and learn about Real Life House.

Our regular opening House Hours begin Tuesday, August 25.

On Tuesdays, drop in for Coffee and Conversation from 4 to 6 PM, with House Hours continuing until 9 PM.

On Wednesdays and Thursdays, the House will be open from 4 to 9 PM.

These are our starting hours. We plan to add more daytime and evening hours as the semester gets underway and our team grows.

And here is an easy way to know when you can stop in: if you see our Host Is In, Coffee Is On, Drop By Now sign outside, come on in. You do not need an appointment or a special reason to visit.

For the latest hours and updates, visit RealLifeHouse dot org.',
    'speak',
    NULL
);

INSERT INTO ivr_menu_options (digit, menu_option_name, script_text, action_type, action_param)
VALUES (
    '2',
    'Real Life Sundays',
    'Real Life at the House meets Sunday evenings beginning at 7:45 PM.

These evenings are built around Christian community, Scripture, discussion, worship, prayer, fellowship, and life together.

Our first Sunday gathering is August 30, Welcome to the House.

On September 6 and September 13, we will continue with welcome evenings and a short devotional as students get settled into the semester.

Then, beginning September 20, Real Life Nights begin with the series, And You Thought You Knew Him, Discovering Jesus through the Gospel of Mark.

Beginning September 20, we will spend Sunday evenings walking through the Gospel of Mark, encountering Jesus as Mark presents Him and asking again the question at the heart of the Gospel: Who is this man?

Whether you have been following Christ for years, are trying to figure out what you believe, or simply want a place to meet people and have meaningful conversations, you are welcome.

For the latest Sunday schedule, visit RealLifeHouse dot org.',
    'speak',
    NULL
);

INSERT INTO ivr_menu_options (digit, menu_option_name, script_text, action_type, action_param)
VALUES (
    '3',
    'About Real Life House',
    'Real Life House is a Christian Study Center and Hospitality House serving the Anderson University community.

We exist to help people know Christ more deeply, become more like Him, and make Him known.

The House is a place to study, have coffee, meet friends, talk with a pastor or mentor, ask honest questions, participate in Bible studies and discussions, or simply find a welcoming place to spend some time.

You do not have to be part of a particular church, organization, or program to walk through the door.

Sometimes there will be something scheduled. Sometimes there will simply be coffee, conversation, and a place to sit.

That is part of what we mean when we say: Come in. Sit down. Stay awhile.

Learn more at RealLifeHouse dot org.',
    'speak',
    NULL
);

INSERT INTO ivr_menu_options (digit, menu_option_name, script_text, action_type, action_param)
VALUES (
    '4',
    'Get Involved',
    'There are several ways to help build the community at Real Life House as we begin this fall.

We are looking for people interested in volunteering at the House, helping with hospitality and events, serving students, assisting with music and worship, and helping with other practical needs.

We are also developing internship and student leadership opportunities for those who would like to serve while gaining meaningful ministry experience.

Some opportunities require only occasional help, while others can become a regular part of the life of the House.

We also welcome individuals, churches, and friends who would like to partner with Real Life House through ongoing financial support, providing snacks or meals, helping with hospitality needs, or purchasing items from our current-needs Amazon list.

If you are interested in serving, interning, helping with music, providing food or snacks, or supporting the work of Real Life House, please leave us a message using option 6.

You can also visit RealLifeHouse dot org for current information and ways to connect.',
    'speak',
    NULL
);

INSERT INTO ivr_menu_options (digit, menu_option_name, script_text, action_type, action_param)
VALUES (
    '5',
    'Location & Website',
    'Real Life House is located at 206 Williamston Road in Anderson, South Carolina, in the Anderson University community.

Our website is RealLifeHouse dot org.

There you will find current House Hours, upcoming gatherings, Real Life Sunday information, formation opportunities, and ways to get involved.

And remember, when you are nearby and the Host Is In, Coffee Is On, Drop By Now sign is out, you are invited to come in.

We would love to meet you.',
    'speak',
    NULL
);

INSERT INTO ivr_menu_options (digit, menu_option_name, script_text, action_type, action_param)
VALUES (
    '6',
    'Leave a Message',
    'We would love to hear from you.

After the tone, please leave your name, phone number, and a brief message, and someone from Real Life House will get back with you as soon as we can.

If you are calling about volunteering, an internship, music or worship, providing food or snacks, ongoing support, or another way you would like to help, please mention that in your message.

You can also find current information at RealLifeHouse dot org.

Thanks for calling Real Life House.

Come in. Sit down. Stay awhile.',
    'voicemail',
    'general'
);

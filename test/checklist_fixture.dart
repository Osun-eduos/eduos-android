// The inspection checklist as eduos-api serves it (GET /inspections/template), copied for tests.
// ignore_for_file: prefer_single_quotes
const checklistJson = {
 "version": 1,
 "ratings": [
  {
   "value": "GOOD",
   "label": "Good"
  },
  {
   "value": "FAIR",
   "label": "Fair"
  },
  {
   "value": "POOR",
   "label": "Poor"
  },
  {
   "value": "UNUSABLE",
   "label": "Unusable"
  }
 ],
 "sections": [
  {
   "key": "classrooms",
   "title": "Classrooms",
   "items": [
    {
     "key": "total",
     "label": "Number of classrooms",
     "type": "count"
    },
    {
     "key": "usable",
     "label": "Classrooms safe to use",
     "type": "count"
    },
    {
     "key": "condition",
     "label": "General condition",
     "type": "rating"
    },
    {
     "key": "roofLeaks",
     "label": "Roof leaks",
     "type": "yesno"
    },
    {
     "key": "enoughSeats",
     "label": "Enough desks and chairs for the pupils",
     "type": "yesno"
    },
    {
     "key": "boards",
     "label": "Chalkboards or whiteboards",
     "type": "rating"
    }
   ]
  },
  {
   "key": "toilets",
   "title": "Toilets",
   "items": [
    {
     "key": "girls",
     "label": "Toilets for girls",
     "type": "count"
    },
    {
     "key": "boys",
     "label": "Toilets for boys",
     "type": "count"
    },
    {
     "key": "staff",
     "label": "Toilets for staff",
     "type": "count"
    },
    {
     "key": "working",
     "label": "Toilets working",
     "type": "count",
     "hint": "Of all the toilets above"
    },
    {
     "key": "condition",
     "label": "Cleanliness and condition",
     "type": "rating"
    },
    {
     "key": "handwashing",
     "label": "Handwashing with water and soap",
     "type": "yesno"
    }
   ]
  },
  {
   "key": "water",
   "title": "Water",
   "items": [
    {
     "key": "source",
     "label": "Main water source",
     "type": "choice",
     "options": [
      {
       "value": "NONE",
       "label": "None"
      },
      {
       "value": "BOREHOLE",
       "label": "Borehole"
      },
      {
       "value": "WELL",
       "label": "Well"
      },
      {
       "value": "PIPED",
       "label": "Piped"
      },
      {
       "value": "TANKER",
       "label": "Tanker or vendor"
      },
      {
       "value": "RAIN",
       "label": "Rainwater"
      }
     ]
    },
    {
     "key": "working",
     "label": "Water available on the day",
     "type": "yesno"
    },
    {
     "key": "safe",
     "label": "Safe to drink",
     "type": "yesno"
    }
   ]
  },
  {
   "key": "power",
   "title": "Power",
   "items": [
    {
     "key": "source",
     "label": "Main power source",
     "type": "choice",
     "options": [
      {
       "value": "NONE",
       "label": "None"
      },
      {
       "value": "GRID",
       "label": "Grid"
      },
      {
       "value": "SOLAR",
       "label": "Solar"
      },
      {
       "value": "GENERATOR",
       "label": "Generator"
      }
     ]
    },
    {
     "key": "working",
     "label": "Power available on the day",
     "type": "yesno"
    }
   ]
  },
  {
   "key": "safety",
   "title": "Safety and grounds",
   "items": [
    {
     "key": "fence",
     "label": "Perimeter fence",
     "type": "choice",
     "options": [
      {
       "value": "NONE",
       "label": "None"
      },
      {
       "value": "PARTIAL",
       "label": "Partial"
      },
      {
       "value": "FULL",
       "label": "Full"
      }
     ]
    },
    {
     "key": "gate",
     "label": "Gate that closes",
     "type": "yesno"
    },
    {
     "key": "firstAid",
     "label": "First aid box",
     "type": "yesno"
    },
    {
     "key": "fireExtinguisher",
     "label": "Working fire extinguisher",
     "type": "yesno"
    },
    {
     "key": "hazards",
     "label": "Dangerous structures (cracked walls, exposed wiring, open pits)",
     "type": "yesno"
    }
   ]
  },
  {
   "key": "facilities",
   "title": "Other facilities",
   "items": [
    {
     "key": "library",
     "label": "Library",
     "type": "yesno"
    },
    {
     "key": "laboratory",
     "label": "Science laboratory",
     "type": "yesno"
    },
    {
     "key": "ict",
     "label": "Computer room",
     "type": "yesno"
    },
    {
     "key": "playground",
     "label": "Playground or sports field",
     "type": "yesno"
    }
   ]
  }
 ]
};

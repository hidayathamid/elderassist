// Mock data for the caregiving ecosystem

export const caregivers = [
  {
    id: "cg1",
    name: "Sarah Johnson",
    photo: "https://images.unsplash.com/photo-1559839734-2b71ea197ec2?w=200&h=200&fit=crop&crop=face",
    rating: 4.9,
    specialization: "Elderly Care",
    distance: "1.2 km",
    available: true,
    price: "RM 80/session",
    eta: "15 min",
    experience: "5 years",
    completedJobs: 248,
  },
  {
    id: "cg2",
    name: "Ahmad Rahman",
    photo: "https://images.unsplash.com/photo-1612349317150-e413f6a5b16d?w=200&h=200&fit=crop&crop=face",
    rating: 4.8,
    specialization: "Medical Care",
    distance: "2.5 km",
    available: true,
    price: "RM 100/session",
    eta: "20 min",
    experience: "8 years",
    completedJobs: 512,
  },
  {
    id: "cg3",
    name: "Maria Santos",
    photo: "https://images.unsplash.com/photo-1594824476967-48c8b964273f?w=200&h=200&fit=crop&crop=face",
    rating: 4.7,
    specialization: "Physical Therapy",
    distance: "3.1 km",
    available: false,
    price: "RM 120/session",
    eta: "25 min",
    experience: "6 years",
    completedJobs: 189,
  },
  {
    id: "cg4",
    name: "David Lee",
    photo: "https://images.unsplash.com/photo-1622253692010-333f2da6031d?w=200&h=200&fit=crop&crop=face",
    rating: 4.9,
    specialization: "Dementia Care",
    distance: "0.8 km",
    available: true,
    price: "RM 90/session",
    eta: "10 min",
    experience: "7 years",
    completedJobs: 320,
  },
  {
    id: "cg5",
    name: "Fatimah Binti Ali",
    photo: "https://images.unsplash.com/photo-1651008376811-b90baee60c1f?w=200&h=200&fit=crop&crop=face",
    rating: 5.0,
    specialization: "Palliative Care",
    distance: "1.5 km",
    available: true,
    price: "RM 150/session",
    eta: "18 min",
    experience: "10 years",
    completedJobs: 456,
  },
];

export const familyMembers = [
  {
    id: "fm1",
    name: "Ahmad (Father)",
    photo: "https://images.unsplash.com/photo-1566616213894-2d4e1baee5d8?w=200&h=200&fit=crop&crop=face",
    age: 75,
    address: "123 Jalan Merdeka, Kuala Lumpur",
    conditions: ["Diabetes", "Hypertension"],
  },
  {
    id: "fm2",
    name: "Siti (Mother)",
    photo: "https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=200&h=200&fit=crop&crop=face",
    age: 72,
    address: "123 Jalan Merdeka, Kuala Lumpur",
    conditions: ["Arthritis"],
  },
  {
    id: "fm3",
    name: "Grandmother Maryam",
    photo: "https://images.unsplash.com/photo-1581579438747-1dc8d17bbce4?w=200&h=200&fit=crop&crop=face",
    age: 88,
    address: "456 Jalan Kampung, Selangor",
    conditions: ["Dementia", "Mobility Issues"],
  },
];

export const bookings = [
  {
    id: "bk1",
    caregiver: caregivers[0],
    familyMember: familyMembers[0],
    date: "2024-12-15",
    time: "09:00 AM",
    status: "scheduled",
    service: "Daily Care",
    price: "RM 80",
    notes: "Morning medication assistance needed",
  },
  {
    id: "bk2",
    caregiver: caregivers[1],
    familyMember: familyMembers[2],
    date: "2024-12-16",
    time: "02:00 PM",
    status: "scheduled",
    service: "Medical Care",
    price: "RM 100",
    notes: "Post-surgery wound care",
  },
  {
    id: "bk3",
    caregiver: caregivers[3],
    familyMember: familyMembers[1],
    date: "2024-12-10",
    time: "10:00 AM",
    status: "completed",
    service: "Dementia Care",
    price: "RM 90",
    notes: "",
  },
];

export const sosAlerts = [
  {
    id: "sos1",
    user: {
      name: "Ahmad Ibrahim",
      photo: "https://images.unsplash.com/photo-1566616213894-2d4e1baee5d8?w=200&h=200&fit=crop&crop=face",
      phone: "+60 12-345 6789",
    },
    location: "123 Jalan Merdeka, Kuala Lumpur",
    distance: "0.8 km",
    status: "active",
    time: "2 min ago",
    type: "Medical Emergency",
  },
  {
    id: "sos2",
    user: {
      name: "Siti Aminah",
      photo: "https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=200&h=200&fit=crop&crop=face",
      phone: "+60 12-987 6543",
    },
    location: "456 Jalan Harmoni, Petaling Jaya",
    distance: "2.3 km",
    status: "pending",
    time: "5 min ago",
    type: "Fall Detection",
  },
];

export const chatMessages = [
  {
    id: "msg1",
    sender: "user",
    message: "Hi, when will you arrive?",
    time: "10:30 AM",
  },
  {
    id: "msg2",
    sender: "caregiver",
    message: "I'm on my way! Should be there in about 15 minutes.",
    time: "10:32 AM",
  },
  {
    id: "msg3",
    sender: "user",
    message: "Great, thank you! Please use the side entrance.",
    time: "10:33 AM",
  },
  {
    id: "msg4",
    sender: "caregiver",
    message: "Understood, see you soon!",
    time: "10:34 AM",
  },
];

export const adminStats = {
  totalUsers: 1250,
  totalCaregivers: 85,
  activeCaregivers: 62,
  completedBookings: 3420,
  pendingBookings: 28,
  sosToday: 3,
  revenue: "RM 125,400",
  monthlyGrowth: 12.5,
};

export const recentActivity = [
  { type: "booking", message: "New booking by Ahmad Ibrahim", time: "5 min ago" },
  { type: "caregiver", message: "Sarah Johnson went online", time: "12 min ago" },
  { type: "sos", message: "SOS resolved - Jalan Merdeka", time: "25 min ago" },
  { type: "payment", message: "Payment received - RM 80", time: "1 hour ago" },
  { type: "review", message: "New 5-star review for Ahmad Rahman", time: "2 hours ago" },
];

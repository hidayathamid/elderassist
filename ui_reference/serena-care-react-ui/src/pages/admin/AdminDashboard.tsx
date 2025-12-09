import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Avatar } from "@/components/shared/Avatar";
import { StatusBadge } from "@/components/shared/StatusBadge";
import { adminStats, recentActivity, caregivers, sosAlerts } from "@/data/mockData";
import {
  Users, UserCheck, Calendar, AlertTriangle, DollarSign,
  TrendingUp, Clock, CheckCircle, XCircle, MapPin
} from "lucide-react";

const AdminDashboard = () => {
  const statCards = [
    { label: "Total Users", value: adminStats.totalUsers.toLocaleString(), icon: Users, color: "primary" },
    { label: "Total Caregivers", value: adminStats.totalCaregivers, icon: UserCheck, color: "success" },
    { label: "Active Caregivers", value: adminStats.activeCaregivers, icon: UserCheck, color: "success" },
    { label: "Completed Bookings", value: adminStats.completedBookings.toLocaleString(), icon: Calendar, color: "primary" },
    { label: "Pending Bookings", value: adminStats.pendingBookings, icon: Clock, color: "warning" },
    { label: "SOS Today", value: adminStats.sosToday, icon: AlertTriangle, color: "emergency" },
  ];

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-foreground">Dashboard</h1>
        <p className="text-muted-foreground">Welcome back! Here's what's happening today.</p>
      </div>

      {/* Stats Grid */}
      <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-4">
        {statCards.map((stat) => (
          <Card key={stat.label} variant="default" padding="sm">
            <div className="flex items-center gap-3">
              <div className={`w-10 h-10 rounded-lg flex items-center justify-center ${
                stat.color === "primary" ? "bg-primary/10" :
                stat.color === "success" ? "bg-success/10" :
                stat.color === "warning" ? "bg-warning/10" :
                "bg-emergency/10"
              }`}>
                <stat.icon className={`h-5 w-5 ${
                  stat.color === "primary" ? "text-primary" :
                  stat.color === "success" ? "text-success" :
                  stat.color === "warning" ? "text-warning" :
                  "text-emergency"
                }`} />
              </div>
              <div>
                <p className="text-2xl font-bold text-foreground">{stat.value}</p>
                <p className="text-xs text-muted-foreground">{stat.label}</p>
              </div>
            </div>
          </Card>
        ))}
      </div>

      {/* Revenue Card */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <Card variant="stat" padding="default" className="lg:col-span-1">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm opacity-80">Total Revenue</p>
              <p className="text-3xl font-bold mt-1">{adminStats.revenue}</p>
              <div className="flex items-center gap-1 mt-2">
                <TrendingUp className="h-4 w-4" />
                <span className="text-sm">+{adminStats.monthlyGrowth}% this month</span>
              </div>
            </div>
            <DollarSign className="h-12 w-12 opacity-50" />
          </div>
        </Card>

        {/* Monthly Bookings Chart */}
        <Card variant="default" padding="default" className="lg:col-span-2">
          <CardHeader className="p-0 pb-4">
            <CardTitle className="text-lg">Monthly Bookings</CardTitle>
          </CardHeader>
          <div className="flex items-end justify-between h-40 px-2 gap-2">
            {[120, 180, 150, 220, 190, 280, 310, 260, 290, 340, 380, 420].map((value, i) => (
              <div key={i} className="flex-1 flex flex-col items-center">
                <div
                  className="w-full bg-primary/20 rounded-t transition-all duration-500 hover:bg-primary/40"
                  style={{ height: `${(value / 420) * 100}%` }}
                >
                  <div
                    className="w-full bg-primary rounded-t"
                    style={{ height: `${(value / 420) * 80}%` }}
                  />
                </div>
              </div>
            ))}
          </div>
          <div className="flex justify-between text-xs text-muted-foreground mt-2 px-2">
            {["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"].map(m => (
              <span key={m}>{m}</span>
            ))}
          </div>
        </Card>
      </div>

      {/* Three columns */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Recent Activity */}
        <Card variant="default" padding="default">
          <CardHeader className="p-0 pb-4">
            <CardTitle className="text-lg">Recent Activity</CardTitle>
          </CardHeader>
          <div className="space-y-4">
            {recentActivity.map((activity, i) => (
              <div key={i} className="flex items-start gap-3">
                <div className={`w-8 h-8 rounded-full flex items-center justify-center shrink-0 ${
                  activity.type === "booking" ? "bg-primary/10" :
                  activity.type === "sos" ? "bg-emergency/10" :
                  activity.type === "payment" ? "bg-success/10" :
                  "bg-muted"
                }`}>
                  {activity.type === "booking" && <Calendar className="h-4 w-4 text-primary" />}
                  {activity.type === "sos" && <AlertTriangle className="h-4 w-4 text-emergency" />}
                  {activity.type === "payment" && <DollarSign className="h-4 w-4 text-success" />}
                  {activity.type === "caregiver" && <UserCheck className="h-4 w-4 text-primary" />}
                  {activity.type === "review" && <CheckCircle className="h-4 w-4 text-warning" />}
                </div>
                <div className="flex-1 min-w-0">
                  <p className="text-sm text-foreground">{activity.message}</p>
                  <p className="text-xs text-muted-foreground">{activity.time}</p>
                </div>
              </div>
            ))}
          </div>
        </Card>

        {/* Active SOS Alerts */}
        <Card variant="default" padding="default">
          <CardHeader className="p-0 pb-4">
            <div className="flex items-center justify-between">
              <CardTitle className="text-lg">Active SOS Alerts</CardTitle>
              <Badge variant="emergency">{sosAlerts.length} Active</Badge>
            </div>
          </CardHeader>
          <div className="space-y-3">
            {sosAlerts.map((alert) => (
              <Card key={alert.id} variant="emergency" padding="sm">
                <div className="flex items-start gap-3">
                  <Avatar src={alert.user.photo} name={alert.user.name} size="sm" />
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center justify-between">
                      <p className="font-medium text-foreground">{alert.user.name}</p>
                      <Badge variant={alert.status === "active" ? "emergency" : "pending"}>
                        {alert.status}
                      </Badge>
                    </div>
                    <p className="text-xs text-muted-foreground">{alert.type}</p>
                    <div className="flex items-center gap-1 mt-1 text-xs text-muted-foreground">
                      <MapPin className="h-3 w-3" />
                      <span className="truncate">{alert.location}</span>
                    </div>
                  </div>
                </div>
              </Card>
            ))}
          </div>
        </Card>

        {/* Top Caregivers */}
        <Card variant="default" padding="default">
          <CardHeader className="p-0 pb-4">
            <CardTitle className="text-lg">Top Caregivers</CardTitle>
          </CardHeader>
          <div className="space-y-3">
            {caregivers.slice(0, 4).map((caregiver, i) => (
              <div key={caregiver.id} className="flex items-center gap-3">
                <span className="w-6 h-6 bg-muted rounded-full flex items-center justify-center text-xs font-bold">
                  {i + 1}
                </span>
                <Avatar src={caregiver.photo} name={caregiver.name} size="sm" />
                <div className="flex-1 min-w-0">
                  <p className="font-medium text-foreground text-sm">{caregiver.name}</p>
                  <p className="text-xs text-muted-foreground">{caregiver.completedJobs} jobs</p>
                </div>
                <div className="flex items-center gap-1">
                  <span className="text-sm font-medium text-foreground">{caregiver.rating}</span>
                  <span className="text-warning">★</span>
                </div>
              </div>
            ))}
          </div>
        </Card>
      </div>

      {/* Caregiver Distribution Map Placeholder */}
      <Card variant="default" padding="default">
        <CardHeader className="p-0 pb-4">
          <CardTitle className="text-lg">Caregiver Distribution</CardTitle>
        </CardHeader>
        <div className="h-64 bg-muted rounded-lg flex items-center justify-center">
          <div className="text-center">
            <MapPin className="h-12 w-12 text-primary/50 mx-auto mb-2" />
            <p className="text-muted-foreground">Map showing caregiver locations</p>
            <p className="text-sm text-muted-foreground">62 caregivers online across 15 areas</p>
          </div>
        </div>
      </Card>
    </div>
  );
};

export default AdminDashboard;

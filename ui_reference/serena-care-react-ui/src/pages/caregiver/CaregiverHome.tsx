import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { Header } from "@/components/shared/Header";
import { CaregiverNav } from "@/components/shared/MobileNav";
import { StatusBadge } from "@/components/shared/StatusBadge";
import { Avatar } from "@/components/shared/Avatar";
import { QuickActionCard } from "@/components/shared/QuickActionCard";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Switch } from "@/components/ui/switch";
import { bookings, caregivers } from "@/data/mockData";
import { 
  Calendar, DollarSign, Star, Clock, MapPin, 
  ChevronRight, Play, TrendingUp 
} from "lucide-react";

const CaregiverHome = () => {
  const navigate = useNavigate();
  const [isOnline, setIsOnline] = useState(true);
  const caregiver = caregivers[0];

  const todayJob = bookings[0];

  const stats = {
    completedJobs: 248,
    monthlyEarnings: "RM 4,200",
    rating: 4.9,
  };

  return (
    <div className="min-h-screen bg-background pb-24">
      <Header
        greeting="Good morning,"
        subtitle={caregiver.name}
        avatar={caregiver.photo}
        notificationCount={5}
      />

      <main className="px-4 py-6 space-y-6">
        {/* Availability Toggle */}
        <Card variant="default" padding="sm">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <div className={`w-3 h-3 rounded-full ${isOnline ? "bg-success" : "bg-muted-foreground"}`} />
              <div>
                <p className="font-semibold text-foreground">
                  {isOnline ? "You're Online" : "You're Offline"}
                </p>
                <p className="text-sm text-muted-foreground">
                  {isOnline ? "Accepting job requests" : "Not accepting requests"}
                </p>
              </div>
            </div>
            <Switch checked={isOnline} onCheckedChange={setIsOnline} />
          </div>
        </Card>

        {/* Today's Job Card */}
        {todayJob && (
          <section>
            <h2 className="text-lg font-bold text-foreground mb-3">Today's Job</h2>
            <Card variant="action" padding="sm" onClick={() => navigate("/caregiver/jobs")}>
              <div className="flex items-start gap-3 mb-4">
                <Avatar src={todayJob.familyMember.photo} name={todayJob.familyMember.name} size="lg" />
                <div className="flex-1">
                  <h4 className="font-semibold text-foreground">{todayJob.familyMember.name}</h4>
                  <div className="flex items-center gap-2 text-sm text-muted-foreground mt-1">
                    <Clock className="h-4 w-4" />
                    <span>{todayJob.time}</span>
                  </div>
                  <div className="flex items-center gap-2 text-sm text-muted-foreground mt-1">
                    <MapPin className="h-4 w-4" />
                    <span className="truncate">{todayJob.familyMember.address}</span>
                  </div>
                </div>
                <StatusBadge status="scheduled" />
              </div>
              <Button size="full">
                View Job Details
                <ChevronRight className="h-4 w-4 ml-2" />
              </Button>
            </Card>
          </section>
        )}

        {/* Quick Actions */}
        <section>
          <h2 className="text-lg font-bold text-foreground mb-3">Quick Actions</h2>
          <div className="grid grid-cols-3 gap-3">
            <QuickActionCard
              icon={Play}
              title="Start Day"
              variant="primary"
              onClick={() => {}}
            />
            <QuickActionCard
              icon={Calendar}
              title="Schedule"
              variant="default"
              onClick={() => navigate("/caregiver/jobs")}
            />
            <QuickActionCard
              icon={DollarSign}
              title="Earnings"
              variant="success"
              onClick={() => navigate("/caregiver/profile")}
            />
          </div>
        </section>

        {/* Stats Preview */}
        <section>
          <h2 className="text-lg font-bold text-foreground mb-3">Your Performance</h2>
          <div className="grid grid-cols-3 gap-3">
            <Card variant="default" padding="sm" className="text-center">
              <div className="w-10 h-10 bg-primary/10 rounded-full flex items-center justify-center mx-auto mb-2">
                <Calendar className="h-5 w-5 text-primary" />
              </div>
              <p className="text-xl font-bold text-foreground">{stats.completedJobs}</p>
              <p className="text-xs text-muted-foreground">Jobs Done</p>
            </Card>
            <Card variant="default" padding="sm" className="text-center">
              <div className="w-10 h-10 bg-success/10 rounded-full flex items-center justify-center mx-auto mb-2">
                <DollarSign className="h-5 w-5 text-success" />
              </div>
              <p className="text-xl font-bold text-foreground">{stats.monthlyEarnings}</p>
              <p className="text-xs text-muted-foreground">This Month</p>
            </Card>
            <Card variant="default" padding="sm" className="text-center">
              <div className="w-10 h-10 bg-warning/10 rounded-full flex items-center justify-center mx-auto mb-2">
                <Star className="h-5 w-5 text-warning" />
              </div>
              <p className="text-xl font-bold text-foreground">{stats.rating}</p>
              <p className="text-xs text-muted-foreground">Rating</p>
            </Card>
          </div>
        </section>

        {/* Earnings Trend */}
        <Card variant="default" padding="sm">
          <div className="flex items-center justify-between mb-4">
            <h3 className="font-semibold text-foreground">Earnings Trend</h3>
            <Badge variant="available" className="flex items-center gap-1">
              <TrendingUp className="h-3 w-3" />
              +12%
            </Badge>
          </div>
          <div className="flex items-end justify-between h-24 px-2">
            {[40, 65, 45, 80, 55, 70, 90].map((height, i) => (
              <div
                key={i}
                className="w-6 bg-primary/20 rounded-t"
                style={{ height: `${height}%` }}
              >
                <div
                  className="w-full bg-primary rounded-t transition-all duration-500"
                  style={{ height: `${height}%` }}
                />
              </div>
            ))}
          </div>
          <div className="flex justify-between text-xs text-muted-foreground mt-2 px-2">
            <span>Mon</span>
            <span>Tue</span>
            <span>Wed</span>
            <span>Thu</span>
            <span>Fri</span>
            <span>Sat</span>
            <span>Sun</span>
          </div>
        </Card>
      </main>

      <CaregiverNav />
    </div>
  );
};

// Import Badge for the trending component
import { Badge } from "@/components/ui/badge";

export default CaregiverHome;

import { useState } from "react";
import { Header } from "@/components/shared/Header";
import { CaregiverNav } from "@/components/shared/MobileNav";
import { Avatar } from "@/components/shared/Avatar";
import { StatusBadge } from "@/components/shared/StatusBadge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Switch } from "@/components/ui/switch";
import { caregivers } from "@/data/mockData";
import { 
  User, Star, DollarSign, Calendar, Clock, 
  MapPin, Settings, HelpCircle, FileText, Shield, 
  LogOut, ChevronRight, Edit, CreditCard, Award
} from "lucide-react";

const CaregiverProfile = () => {
  const [isOnline, setIsOnline] = useState(true);
  const caregiver = caregivers[0];

  const stats = {
    totalEarnings: "RM 24,500",
    weeklyEarnings: "RM 1,200",
    avgPerJob: "RM 85",
    totalJobs: 248,
    thisMonth: 32,
    rating: 4.9,
    reviews: 186,
  };

  const certifications = [
    "First Aid Certified",
    "Elderly Care Training",
    "CPR Certified",
  ];

  const serviceTypes = [
    "Elderly Care",
    "Medical Care",
    "Physical Therapy",
    "Companionship",
  ];

  return (
    <div className="min-h-screen bg-background pb-24">
      <Header title="Profile" showNotification={false} />

      <main className="px-4 py-4 space-y-6">
        {/* Profile Header */}
        <Card variant="default" padding="sm">
          <div className="flex items-center gap-4 mb-4">
            <Avatar
              src={caregiver.photo}
              name={caregiver.name}
              size="xl"
              showBorder
              status={isOnline ? "online" : "offline"}
            />
            <div className="flex-1">
              <h2 className="text-xl font-bold text-foreground">{caregiver.name}</h2>
              <p className="text-muted-foreground">{caregiver.specialization}</p>
              <div className="flex items-center gap-2 mt-1">
                <Star className="h-4 w-4 text-warning fill-warning" />
                <span className="font-medium">{stats.rating}</span>
                <span className="text-muted-foreground">({stats.reviews} reviews)</span>
              </div>
            </div>
          </div>

          {/* Availability Toggle */}
          <div className="flex items-center justify-between p-3 bg-muted/50 rounded-lg">
            <div className="flex items-center gap-2">
              <StatusBadge status={isOnline ? "online" : "offline"} />
            </div>
            <Switch checked={isOnline} onCheckedChange={setIsOnline} />
          </div>

          <Button variant="outline" size="full" className="mt-4">
            <Edit className="h-4 w-4 mr-2" />
            Edit Profile
          </Button>
        </Card>

        {/* Earnings Dashboard */}
        <section>
          <h3 className="font-semibold text-foreground mb-3">Earnings</h3>
          <div className="grid grid-cols-3 gap-3">
            <Card variant="stat" padding="sm" className="text-center">
              <DollarSign className="h-5 w-5 mx-auto mb-1 opacity-80" />
              <p className="text-lg font-bold">{stats.totalEarnings}</p>
              <p className="text-xs opacity-80">Total</p>
            </Card>
            <Card variant="default" padding="sm" className="text-center">
              <p className="text-lg font-bold text-foreground">{stats.weeklyEarnings}</p>
              <p className="text-xs text-muted-foreground">This Week</p>
            </Card>
            <Card variant="default" padding="sm" className="text-center">
              <p className="text-lg font-bold text-foreground">{stats.avgPerJob}</p>
              <p className="text-xs text-muted-foreground">Avg/Job</p>
            </Card>
          </div>
        </section>

        {/* Job Stats */}
        <section>
          <h3 className="font-semibold text-foreground mb-3">Performance</h3>
          <Card variant="default" padding="sm">
            <div className="grid grid-cols-2 gap-4">
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 bg-primary/10 rounded-full flex items-center justify-center">
                  <Calendar className="h-5 w-5 text-primary" />
                </div>
                <div>
                  <p className="text-xl font-bold text-foreground">{stats.totalJobs}</p>
                  <p className="text-xs text-muted-foreground">Total Jobs</p>
                </div>
              </div>
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 bg-success/10 rounded-full flex items-center justify-center">
                  <Calendar className="h-5 w-5 text-success" />
                </div>
                <div>
                  <p className="text-xl font-bold text-foreground">{stats.thisMonth}</p>
                  <p className="text-xs text-muted-foreground">This Month</p>
                </div>
              </div>
            </div>
          </Card>
        </section>

        {/* Certifications */}
        <section>
          <h3 className="font-semibold text-foreground mb-3">Certifications</h3>
          <Card variant="default" padding="sm">
            <div className="flex flex-wrap gap-2">
              {certifications.map((cert) => (
                <Badge key={cert} variant="success" className="gap-1">
                  <Award className="h-3 w-3" />
                  {cert}
                </Badge>
              ))}
            </div>
          </Card>
        </section>

        {/* Service Types */}
        <section>
          <h3 className="font-semibold text-foreground mb-3">Services Offered</h3>
          <Card variant="default" padding="sm">
            <div className="flex flex-wrap gap-2">
              {serviceTypes.map((service) => (
                <Badge key={service} variant="secondary">
                  {service}
                </Badge>
              ))}
            </div>
          </Card>
        </section>

        {/* Menu Items */}
        <section>
          <h3 className="font-semibold text-foreground mb-3">Settings</h3>
          <Card variant="default" padding="none">
            {[
              { icon: Clock, label: "Availability Schedule" },
              { icon: MapPin, label: "Working Areas" },
              { icon: CreditCard, label: "Payment Methods" },
              { icon: FileText, label: "Documents" },
            ].map((item, index) => (
              <button
                key={item.label}
                className={`w-full flex items-center gap-4 px-4 py-4 hover:bg-muted/50 transition-colors ${
                  index !== 3 ? "border-b border-border" : ""
                }`}
              >
                <item.icon className="h-5 w-5 text-primary" />
                <span className="flex-1 text-left font-medium text-foreground">{item.label}</span>
                <ChevronRight className="h-5 w-5 text-muted-foreground" />
              </button>
            ))}
          </Card>
        </section>

        {/* Support */}
        <section>
          <h3 className="font-semibold text-foreground mb-3">Support</h3>
          <Card variant="default" padding="none">
            {[
              { icon: HelpCircle, label: "Help Center" },
              { icon: FileText, label: "FAQ" },
              { icon: Shield, label: "Privacy Policy" },
            ].map((item, index) => (
              <button
                key={item.label}
                className={`w-full flex items-center gap-4 px-4 py-4 hover:bg-muted/50 transition-colors ${
                  index !== 2 ? "border-b border-border" : ""
                }`}
              >
                <item.icon className="h-5 w-5 text-muted-foreground" />
                <span className="flex-1 text-left font-medium text-foreground">{item.label}</span>
                <ChevronRight className="h-5 w-5 text-muted-foreground" />
              </button>
            ))}
          </Card>
        </section>

        {/* Logout */}
        <Button variant="emergency" size="full">
          <LogOut className="h-5 w-5 mr-2" />
          Logout
        </Button>
      </main>

      <CaregiverNav />
    </div>
  );
};

export default CaregiverProfile;

import { useNavigate } from "react-router-dom";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Heart, Users, Shield, Smartphone, Monitor, ArrowRight } from "lucide-react";

const Index = () => {
  const navigate = useNavigate();

  const apps = [
    {
      id: "client",
      title: "Client App",
      subtitle: "For Families",
      description: "Book caregivers, track appointments, and access emergency SOS",
      icon: Smartphone,
      color: "primary",
      path: "/client",
    },
    {
      id: "caregiver",
      title: "Caregiver App",
      subtitle: "For Care Providers",
      description: "Manage jobs, respond to emergencies, and track earnings",
      icon: Heart,
      color: "success",
      path: "/caregiver",
    },
    {
      id: "admin",
      title: "Admin Panel",
      subtitle: "For Administrators",
      description: "Full dashboard to manage users, caregivers, bookings, and SOS alerts",
      icon: Monitor,
      color: "primary",
      path: "/admin",
    },
  ];

  return (
    <div className="min-h-screen bg-background">
      {/* Hero */}
      <header className="relative overflow-hidden bg-gradient-to-br from-primary/5 via-background to-success/5">
        <div className="container mx-auto px-6 py-20 text-center">
          <Badge variant="match" className="mb-4">Complete Caregiving Ecosystem</Badge>
          <h1 className="text-4xl md:text-5xl font-bold text-foreground mb-4">
            CareConnect
          </h1>
          <p className="text-xl text-muted-foreground max-w-2xl mx-auto mb-8">
            A comprehensive caregiving platform connecting families with professional caregivers through mobile apps and admin management.
          </p>
          <div className="flex items-center justify-center gap-4 text-sm text-muted-foreground">
            <div className="flex items-center gap-2">
              <Shield className="h-4 w-4 text-success" />
              <span>Verified Caregivers</span>
            </div>
            <div className="flex items-center gap-2">
              <Users className="h-4 w-4 text-primary" />
              <span>Family-Focused</span>
            </div>
            <div className="flex items-center gap-2">
              <Heart className="h-4 w-4 text-emergency" />
              <span>24/7 SOS Support</span>
            </div>
          </div>
        </div>
      </header>

      {/* App Selection */}
      <main className="container mx-auto px-6 py-12">
        <h2 className="text-2xl font-bold text-foreground text-center mb-8">
          Choose an Application to Preview
        </h2>
        <div className="grid md:grid-cols-3 gap-6 max-w-5xl mx-auto">
          {apps.map((app) => (
            <Card
              key={app.id}
              variant="action"
              padding="lg"
              className="text-center hover:scale-[1.02] transition-transform"
              onClick={() => navigate(app.path)}
            >
              <div className={`w-16 h-16 rounded-2xl flex items-center justify-center mx-auto mb-4 ${
                app.color === "primary" ? "bg-primary/10" : "bg-success/10"
              }`}>
                <app.icon className={`h-8 w-8 ${
                  app.color === "primary" ? "text-primary" : "text-success"
                }`} />
              </div>
              <h3 className="text-xl font-bold text-foreground mb-1">{app.title}</h3>
              <Badge variant="secondary" className="mb-3">{app.subtitle}</Badge>
              <p className="text-muted-foreground text-sm mb-4">{app.description}</p>
              <Button className="w-full">
                Open App
                <ArrowRight className="h-4 w-4 ml-2" />
              </Button>
            </Card>
          ))}
        </div>

        {/* Features */}
        <div className="mt-16 text-center">
          <h2 className="text-xl font-bold text-foreground mb-6">Design System Features</h2>
          <div className="flex flex-wrap justify-center gap-3">
            <Badge variant="default">Medical UI Theme</Badge>
            <Badge variant="available">Elderly-Friendly</Badge>
            <Badge variant="emergency">SOS System</Badge>
            <Badge variant="success">Booking Flow</Badge>
            <Badge variant="scheduled">Live Tracking</Badge>
            <Badge variant="match">Responsive Design</Badge>
          </div>
        </div>
      </main>
    </div>
  );
};

export default Index;

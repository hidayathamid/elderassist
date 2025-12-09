import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { Header } from "@/components/shared/Header";
import { CaregiverNav } from "@/components/shared/MobileNav";
import { Avatar } from "@/components/shared/Avatar";
import { BottomSheet } from "@/components/shared/BottomSheet";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { sosAlerts } from "@/data/mockData";
import { 
  AlertTriangle, MapPin, Clock, Phone, MessageCircle, 
  Navigation, CheckCircle, XCircle
} from "lucide-react";

const CaregiverSOSAlerts = () => {
  const navigate = useNavigate();
  const [showAlert, setShowAlert] = useState(true);
  const [activeEmergency, setActiveEmergency] = useState<typeof sosAlerts[0] | null>(null);
  const [emergencyStatus, setEmergencyStatus] = useState<"responding" | "arrived" | "started" | "resolved">("responding");

  const currentAlert = sosAlerts[0];

  const handleAcceptEmergency = () => {
    setShowAlert(false);
    setActiveEmergency(currentAlert);
    setEmergencyStatus("responding");
  };

  const handleDeclineEmergency = () => {
    setShowAlert(false);
  };

  const progressEmergency = () => {
    const statuses: typeof emergencyStatus[] = ["responding", "arrived", "started", "resolved"];
    const currentIndex = statuses.indexOf(emergencyStatus);
    if (currentIndex < statuses.length - 1) {
      setEmergencyStatus(statuses[currentIndex + 1]);
    }
  };

  const getActionButton = () => {
    switch (emergencyStatus) {
      case "responding":
        return { label: "Mark Arrived", icon: CheckCircle };
      case "arrived":
        return { label: "Start Emergency Session", icon: AlertTriangle };
      case "started":
        return { label: "End Emergency Session", icon: CheckCircle };
      default:
        return null;
    }
  };

  const actionButton = getActionButton();

  return (
    <div className="min-h-screen bg-background pb-24">
      <Header title="SOS Alerts" showNotification notificationCount={sosAlerts.length} />

      <main className="px-4 py-4">
        {/* Active Emergency Response */}
        {activeEmergency && emergencyStatus !== "resolved" ? (
          <div className="space-y-4">
            {/* Status Banner */}
            <Card variant="emergency" padding="sm">
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 bg-emergency rounded-full flex items-center justify-center animate-pulse">
                  <AlertTriangle className="h-5 w-5 text-emergency-foreground" />
                </div>
                <div>
                  <p className="font-semibold text-foreground">Emergency Response Active</p>
                  <p className="text-sm text-muted-foreground">
                    {emergencyStatus === "responding" && "En route to location"}
                    {emergencyStatus === "arrived" && "Arrived - Ready to assist"}
                    {emergencyStatus === "started" && "Session in progress"}
                  </p>
                </div>
              </div>
            </Card>

            {/* Map View */}
            <Card variant="default" padding="none" className="h-[35vh] relative overflow-hidden">
              <div className="absolute inset-0 bg-gradient-to-b from-emergency/5 to-emergency/20 flex items-center justify-center">
                <div className="text-center">
                  <Navigation className="h-12 w-12 text-emergency mx-auto mb-2" />
                  <p className="text-muted-foreground">Route to Emergency</p>
                  <Badge variant="emergency" className="mt-2">ETA: 5 min</Badge>
                </div>
              </div>
            </Card>

            {/* User Info */}
            <Card variant="default" padding="sm">
              <div className="flex items-center gap-4 mb-4">
                <Avatar src={activeEmergency.user.photo} name={activeEmergency.user.name} size="lg" />
                <div className="flex-1">
                  <h4 className="font-semibold text-foreground">{activeEmergency.user.name}</h4>
                  <p className="text-sm text-muted-foreground">{activeEmergency.type}</p>
                </div>
                <Badge variant="emergency">{activeEmergency.distance}</Badge>
              </div>

              <div className="flex items-center gap-2 text-sm text-muted-foreground mb-4">
                <MapPin className="h-4 w-4" />
                <span>{activeEmergency.location}</span>
              </div>

              <div className="flex gap-2">
                <Button variant="success" size="icon">
                  <Phone className="h-5 w-5" />
                </Button>
                <Button variant="outline" size="icon">
                  <MessageCircle className="h-5 w-5" />
                </Button>
                {actionButton && (
                  <Button 
                    variant={emergencyStatus === "started" ? "success" : "emergency"} 
                    className="flex-1"
                    onClick={progressEmergency}
                  >
                    <actionButton.icon className="h-5 w-5 mr-2" />
                    {actionButton.label}
                  </Button>
                )}
              </div>
            </Card>
          </div>
        ) : emergencyStatus === "resolved" ? (
          <Card variant="success" className="text-center py-8">
            <CheckCircle className="h-12 w-12 text-success mx-auto mb-4" />
            <h3 className="font-semibold text-foreground mb-2">Emergency Resolved</h3>
            <p className="text-muted-foreground mb-4">Great work! You've helped someone in need.</p>
            <Button onClick={() => {
              setActiveEmergency(null);
              setEmergencyStatus("responding");
              setShowAlert(true);
            }}>
              Return to Alerts
            </Button>
          </Card>
        ) : (
          /* No active emergency - show list */
          <div className="space-y-4">
            <Card variant="ghost" className="bg-emergency/5 border border-emergency/20 p-4 rounded-xl">
              <div className="flex items-center gap-3">
                <AlertTriangle className="h-6 w-6 text-emergency" />
                <div>
                  <p className="font-semibold text-foreground">SOS Alerts Enabled</p>
                  <p className="text-sm text-muted-foreground">You'll receive emergency requests nearby</p>
                </div>
              </div>
            </Card>

            <h3 className="font-semibold text-foreground">Recent Alerts</h3>
            {sosAlerts.map((alert) => (
              <Card key={alert.id} variant="default" padding="sm">
                <div className="flex items-start gap-3">
                  <Avatar src={alert.user.photo} name={alert.user.name} size="md" />
                  <div className="flex-1">
                    <div className="flex items-center justify-between">
                      <h4 className="font-semibold text-foreground">{alert.user.name}</h4>
                      <Badge variant={alert.status === "active" ? "emergency" : "secondary"}>
                        {alert.status}
                      </Badge>
                    </div>
                    <p className="text-sm text-muted-foreground">{alert.type}</p>
                    <div className="flex items-center gap-3 mt-2 text-xs text-muted-foreground">
                      <span>{alert.distance}</span>
                      <span>•</span>
                      <span>{alert.time}</span>
                    </div>
                  </div>
                </div>
              </Card>
            ))}
          </div>
        )}
      </main>

      {/* SOS Alert Popup */}
      <BottomSheet
        open={showAlert && !activeEmergency}
        onClose={() => setShowAlert(false)}
        height="auto"
      >
        <div className="text-center mb-6">
          <div className="w-16 h-16 bg-emergency rounded-full flex items-center justify-center mx-auto mb-4 animate-pulse">
            <AlertTriangle className="h-8 w-8 text-emergency-foreground" />
          </div>
          <h2 className="text-xl font-bold text-foreground mb-1">Emergency Alert!</h2>
          <p className="text-muted-foreground">Someone nearby needs urgent help</p>
        </div>

        <div className="space-y-4">
          <div className="flex items-center gap-3">
            <Avatar src={currentAlert.user.photo} name={currentAlert.user.name} size="lg" />
            <div>
              <h4 className="font-semibold text-foreground">{currentAlert.user.name}</h4>
              <p className="text-sm text-muted-foreground">{currentAlert.type}</p>
            </div>
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div className="flex items-center gap-2">
              <MapPin className="h-4 w-4 text-emergency" />
              <span className="text-sm font-medium">{currentAlert.distance}</span>
            </div>
            <div className="flex items-center gap-2">
              <Clock className="h-4 w-4 text-muted-foreground" />
              <span className="text-sm">{currentAlert.time}</span>
            </div>
          </div>

          {/* Mini map preview */}
          <Card variant="ghost" className="bg-muted/50 p-4 rounded-lg">
            <div className="h-20 bg-primary/10 rounded flex items-center justify-center mb-2">
              <MapPin className="h-8 w-8 text-primary/50" />
            </div>
            <p className="text-sm text-muted-foreground text-center">{currentAlert.location}</p>
          </Card>

          <div className="flex gap-3">
            <Button variant="outline" className="flex-1" onClick={handleDeclineEmergency}>
              <XCircle className="h-5 w-5 mr-2" />
              Decline
            </Button>
            <Button variant="emergency" className="flex-1" onClick={handleAcceptEmergency}>
              <CheckCircle className="h-5 w-5 mr-2" />
              Accept
            </Button>
          </div>
        </div>
      </BottomSheet>

      <CaregiverNav />
    </div>
  );
};

export default CaregiverSOSAlerts;

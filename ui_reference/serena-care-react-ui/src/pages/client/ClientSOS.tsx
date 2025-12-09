import { useState, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { Header } from "@/components/shared/Header";
import { Avatar } from "@/components/shared/Avatar";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { caregivers } from "@/data/mockData";
import { AlertTriangle, X, Phone, MessageCircle, MapPin, Clock, CheckCircle2 } from "lucide-react";

type SOSStep = "activate" | "countdown" | "finding" | "tracking" | "resolved";

const ClientSOS = () => {
  const navigate = useNavigate();
  const [step, setStep] = useState<SOSStep>("activate");
  const [countdown, setCountdown] = useState(5);
  const [status, setStatus] = useState("Finding caregiver...");
  const assignedCaregiver = caregivers[3];

  useEffect(() => {
    if (step === "countdown" && countdown > 0) {
      const timer = setTimeout(() => setCountdown(countdown - 1), 1000);
      return () => clearTimeout(timer);
    } else if (step === "countdown" && countdown === 0) {
      setStep("finding");
    }
  }, [step, countdown]);

  useEffect(() => {
    if (step === "finding") {
      const timer = setTimeout(() => {
        setStatus("Caregiver accepted!");
        setTimeout(() => {
          setStatus("Caregiver on the way");
          setStep("tracking");
        }, 1500);
      }, 2000);
      return () => clearTimeout(timer);
    }
  }, [step]);

  const handleActivate = () => {
    setStep("countdown");
    setCountdown(5);
  };

  const handleCancel = () => {
    setStep("activate");
    setCountdown(5);
  };

  const handleResolve = () => {
    setStep("resolved");
  };

  const renderActivate = () => (
    <div className="flex-1 flex flex-col items-center justify-center p-8">
      <div className="text-center mb-12">
        <h1 className="text-2xl font-bold text-foreground mb-2">Emergency SOS</h1>
        <p className="text-muted-foreground">Press and hold the button to activate emergency alert</p>
      </div>

      <button
        onClick={handleActivate}
        className="relative w-40 h-40 rounded-full bg-emergency shadow-float flex items-center justify-center transition-transform hover:scale-105 active:scale-95"
      >
        <div className="absolute inset-0 rounded-full bg-emergency/30 animate-ping" />
        <div className="absolute inset-4 rounded-full bg-emergency/50 animate-pulse" />
        <div className="relative z-10 text-center">
          <AlertTriangle className="h-12 w-12 text-emergency-foreground mx-auto mb-1" />
          <span className="text-lg font-bold text-emergency-foreground">SOS</span>
        </div>
      </button>

      <p className="text-sm text-muted-foreground mt-8 text-center max-w-xs">
        This will alert nearby caregivers and your emergency contacts
      </p>

      <Button variant="ghost" className="mt-8" onClick={() => navigate(-1)}>
        Cancel
      </Button>
    </div>
  );

  const renderCountdown = () => (
    <div className="flex-1 flex flex-col items-center justify-center p-8 bg-emergency/5">
      <div className="text-center mb-8">
        <h1 className="text-xl font-bold text-foreground mb-2">Activating Emergency Alert</h1>
        <p className="text-muted-foreground">Sending in...</p>
      </div>

      <div className="relative w-48 h-48 rounded-full bg-emergency flex items-center justify-center pulse-emergency">
        <span className="text-7xl font-bold text-emergency-foreground">{countdown}</span>
      </div>

      <Button
        variant="outline"
        size="lg"
        className="mt-12"
        onClick={handleCancel}
      >
        <X className="h-5 w-5 mr-2" />
        Cancel
      </Button>
    </div>
  );

  const renderFinding = () => (
    <div className="flex-1 flex flex-col items-center justify-center p-8">
      <div className="relative w-32 h-32 mb-8">
        <div className="absolute inset-0 rounded-full border-4 border-primary/20 animate-ping" />
        <div className="absolute inset-4 rounded-full border-4 border-primary/40 animate-pulse" />
        <div className="absolute inset-8 rounded-full bg-primary flex items-center justify-center">
          <AlertTriangle className="h-8 w-8 text-primary-foreground" />
        </div>
      </div>

      <h1 className="text-xl font-bold text-foreground mb-2">Emergency Alert Sent</h1>
      <p className="text-muted-foreground mb-8">{status}</p>

      <div className="flex items-center gap-2">
        <div className="w-2 h-2 bg-primary rounded-full animate-bounce" style={{ animationDelay: "0ms" }} />
        <div className="w-2 h-2 bg-primary rounded-full animate-bounce" style={{ animationDelay: "150ms" }} />
        <div className="w-2 h-2 bg-primary rounded-full animate-bounce" style={{ animationDelay: "300ms" }} />
      </div>
    </div>
  );

  const renderTracking = () => (
    <div className="flex-1 flex flex-col">
      {/* Map */}
      <div className="h-[50vh] bg-muted relative">
        <div className="absolute inset-0 bg-gradient-to-b from-emergency/5 to-emergency/20 flex items-center justify-center">
          <div className="text-center">
            <div className="w-12 h-12 bg-success rounded-full flex items-center justify-center mx-auto mb-2 animate-bounce-soft">
              <MapPin className="h-6 w-6 text-success-foreground" />
            </div>
            <p className="text-muted-foreground">Caregiver en route</p>
          </div>
        </div>
        
        {/* ETA badge */}
        <div className="absolute top-4 right-4">
          <Badge variant="emergency" className="px-4 py-2 text-sm">
            <Clock className="h-4 w-4 mr-1" />
            ETA: 8 min
          </Badge>
        </div>
      </div>

      {/* Caregiver info */}
      <Card variant="elevated" padding="none" className="-mt-6 rounded-t-3xl flex-1">
        <div className="p-6">
          <Badge variant="success" className="mb-4">Emergency Response Active</Badge>
          
          <div className="flex items-center gap-4 mb-6">
            <Avatar src={assignedCaregiver.photo} name={assignedCaregiver.name} size="xl" status="online" />
            <div className="flex-1">
              <h3 className="text-lg font-bold text-foreground">{assignedCaregiver.name}</h3>
              <p className="text-muted-foreground">{assignedCaregiver.specialization}</p>
              <p className="text-sm text-success font-medium mt-1">On the way • {assignedCaregiver.eta}</p>
            </div>
          </div>

          <div className="grid grid-cols-2 gap-3 mb-6">
            <Button variant="success" size="lg">
              <Phone className="h-5 w-5 mr-2" />
              Call
            </Button>
            <Button variant="outline" size="lg">
              <MessageCircle className="h-5 w-5 mr-2" />
              Chat
            </Button>
          </div>

          <Button variant="emergency" size="full" onClick={handleResolve}>
            Mark as Resolved
          </Button>
        </div>
      </Card>
    </div>
  );

  const renderResolved = () => (
    <div className="flex-1 flex flex-col items-center justify-center p-8">
      <div className="w-24 h-24 bg-success rounded-full flex items-center justify-center mb-6 animate-scale-in">
        <CheckCircle2 className="h-12 w-12 text-success-foreground" />
      </div>

      <h1 className="text-2xl font-bold text-foreground mb-2">Emergency Resolved</h1>
      <p className="text-muted-foreground text-center mb-8">
        We're glad you're safe. Your emergency session has been completed.
      </p>

      <Card variant="success" padding="sm" className="w-full mb-6">
        <div className="flex items-center gap-3">
          <Avatar src={assignedCaregiver.photo} name={assignedCaregiver.name} size="md" />
          <div>
            <p className="font-semibold text-foreground">{assignedCaregiver.name}</p>
            <p className="text-sm text-success">Response time: 8 minutes</p>
          </div>
        </div>
      </Card>

      <Button size="full" onClick={() => navigate("/client")}>
        Return Home
      </Button>
    </div>
  );

  const showHeader = step !== "activate" && step !== "countdown";

  return (
    <div className="min-h-screen bg-background flex flex-col">
      {showHeader && (
        <Header
          title="Emergency SOS"
          showBack={false}
          showNotification={false}
        />
      )}

      {step === "activate" && renderActivate()}
      {step === "countdown" && renderCountdown()}
      {step === "finding" && renderFinding()}
      {step === "tracking" && renderTracking()}
      {step === "resolved" && renderResolved()}
    </div>
  );
};

export default ClientSOS;

import { useState } from "react";
import { Card, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Avatar } from "@/components/shared/Avatar";
import { StatusBadge } from "@/components/shared/StatusBadge";
import { sosAlerts, caregivers } from "@/data/mockData";
import { 
  AlertTriangle, MapPin, Clock, Phone, User, 
  CheckCircle, XCircle, RefreshCcw, FileText 
} from "lucide-react";

const AdminSOSCenter = () => {
  const [selectedAlert, setSelectedAlert] = useState<typeof sosAlerts[0] | null>(sosAlerts[0]);

  const nearbyCaregivers = caregivers.filter(c => c.available).slice(0, 3);

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-foreground">SOS Control Center</h1>
          <p className="text-muted-foreground">Monitor and manage emergency alerts in real-time</p>
        </div>
        <Badge variant="emergency" className="text-lg px-4 py-2">
          {sosAlerts.length} Active Emergencies
        </Badge>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Active Alerts List */}
        <Card variant="default" padding="default" className="lg:col-span-1">
          <CardHeader className="p-0 pb-4">
            <CardTitle className="text-lg flex items-center gap-2">
              <AlertTriangle className="h-5 w-5 text-emergency" />
              Active Alerts
            </CardTitle>
          </CardHeader>
          <div className="space-y-3">
            {sosAlerts.map((alert) => (
              <Card
                key={alert.id}
                variant={selectedAlert?.id === alert.id ? "emergency" : "outline"}
                padding="sm"
                className="cursor-pointer transition-all"
                onClick={() => setSelectedAlert(alert)}
              >
                <div className="flex items-start gap-3">
                  <Avatar src={alert.user.photo} name={alert.user.name} size="sm" />
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center justify-between">
                      <p className="font-medium text-foreground">{alert.user.name}</p>
                      <Badge variant={alert.status === "active" ? "emergency" : "pending"} className="text-[10px]">
                        {alert.status}
                      </Badge>
                    </div>
                    <p className="text-xs text-muted-foreground">{alert.type}</p>
                    <div className="flex items-center gap-2 mt-1 text-xs text-muted-foreground">
                      <Clock className="h-3 w-3" />
                      <span>{alert.time}</span>
                    </div>
                  </div>
                </div>
              </Card>
            ))}
          </div>
        </Card>

        {/* Map View */}
        <Card variant="default" padding="default" className="lg:col-span-2">
          <CardHeader className="p-0 pb-4">
            <CardTitle className="text-lg">Emergency Location</CardTitle>
          </CardHeader>
          <div className="h-[400px] bg-muted rounded-lg relative overflow-hidden">
            <div className="absolute inset-0 bg-gradient-to-b from-emergency/5 to-emergency/20 flex items-center justify-center">
              <div className="text-center">
                <div className="w-16 h-16 bg-emergency rounded-full flex items-center justify-center mx-auto mb-3 animate-pulse">
                  <AlertTriangle className="h-8 w-8 text-emergency-foreground" />
                </div>
                <p className="font-medium text-foreground">Emergency Location</p>
                <p className="text-sm text-muted-foreground">{selectedAlert?.location}</p>
              </div>
            </div>

            {/* User location marker */}
            <div className="absolute top-1/3 left-1/2 -translate-x-1/2 -translate-y-1/2">
              <div className="relative">
                <div className="w-6 h-6 bg-emergency rounded-full flex items-center justify-center animate-pulse">
                  <User className="h-3 w-3 text-emergency-foreground" />
                </div>
                <div className="absolute inset-0 bg-emergency/30 rounded-full animate-ping" />
              </div>
            </div>

            {/* Nearby caregiver markers */}
            {nearbyCaregivers.map((cg, i) => (
              <div
                key={cg.id}
                className="absolute"
                style={{
                  top: `${40 + i * 15}%`,
                  left: `${30 + i * 20}%`,
                }}
              >
                <Avatar src={cg.photo} name={cg.name} size="sm" showBorder />
              </div>
            ))}
          </div>
        </Card>
      </div>

      {/* Selected Alert Details */}
      {selectedAlert && (
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          {/* Alert Info */}
          <Card variant="emergency" padding="default">
            <div className="flex items-center gap-4 mb-4">
              <Avatar src={selectedAlert.user.photo} name={selectedAlert.user.name} size="lg" />
              <div>
                <h3 className="text-lg font-bold text-foreground">{selectedAlert.user.name}</h3>
                <p className="text-muted-foreground">{selectedAlert.user.phone}</p>
              </div>
            </div>
            <div className="space-y-3">
              <div className="flex items-center gap-2">
                <AlertTriangle className="h-4 w-4 text-emergency" />
                <span className="text-sm font-medium">{selectedAlert.type}</span>
              </div>
              <div className="flex items-center gap-2">
                <MapPin className="h-4 w-4 text-muted-foreground" />
                <span className="text-sm">{selectedAlert.location}</span>
              </div>
              <div className="flex items-center gap-2">
                <Clock className="h-4 w-4 text-muted-foreground" />
                <span className="text-sm">Reported {selectedAlert.time}</span>
              </div>
            </div>
            <div className="flex gap-2 mt-4">
              <Button variant="success" size="sm" className="flex-1">
                <Phone className="h-4 w-4 mr-1" />
                Call
              </Button>
              <Button variant="outline" size="sm" className="flex-1">
                <MapPin className="h-4 w-4 mr-1" />
                Navigate
              </Button>
            </div>
          </Card>

          {/* Nearby Caregivers */}
          <Card variant="default" padding="default">
            <CardHeader className="p-0 pb-4">
              <CardTitle className="text-lg">Nearby Caregivers</CardTitle>
            </CardHeader>
            <div className="space-y-3">
              {nearbyCaregivers.map((cg) => (
                <div key={cg.id} className="flex items-center gap-3 p-2 rounded-lg hover:bg-muted/50">
                  <Avatar src={cg.photo} name={cg.name} size="sm" status="online" />
                  <div className="flex-1 min-w-0">
                    <p className="font-medium text-foreground text-sm">{cg.name}</p>
                    <p className="text-xs text-muted-foreground">{cg.distance} away</p>
                  </div>
                  <Button variant="default" size="sm">Assign</Button>
                </div>
              ))}
            </div>
          </Card>

          {/* Status Timeline */}
          <Card variant="default" padding="default">
            <CardHeader className="p-0 pb-4">
              <CardTitle className="text-lg">Status Timeline</CardTitle>
            </CardHeader>
            <div className="space-y-4">
              <div className="flex items-center gap-3">
                <div className="w-8 h-8 bg-emergency rounded-full flex items-center justify-center">
                  <AlertTriangle className="h-4 w-4 text-emergency-foreground" />
                </div>
                <div>
                  <p className="text-sm font-medium">Alert Triggered</p>
                  <p className="text-xs text-muted-foreground">2 min ago</p>
                </div>
              </div>
              <div className="flex items-center gap-3">
                <div className="w-8 h-8 bg-warning/20 rounded-full flex items-center justify-center">
                  <RefreshCcw className="h-4 w-4 text-warning" />
                </div>
                <div>
                  <p className="text-sm font-medium">Finding Caregiver</p>
                  <p className="text-xs text-muted-foreground">In progress</p>
                </div>
              </div>
              <div className="flex items-center gap-3 opacity-50">
                <div className="w-8 h-8 bg-muted rounded-full flex items-center justify-center">
                  <CheckCircle className="h-4 w-4 text-muted-foreground" />
                </div>
                <div>
                  <p className="text-sm font-medium">Caregiver Assigned</p>
                  <p className="text-xs text-muted-foreground">Pending</p>
                </div>
              </div>
              <div className="flex items-center gap-3 opacity-50">
                <div className="w-8 h-8 bg-muted rounded-full flex items-center justify-center">
                  <CheckCircle className="h-4 w-4 text-muted-foreground" />
                </div>
                <div>
                  <p className="text-sm font-medium">Resolved</p>
                  <p className="text-xs text-muted-foreground">Pending</p>
                </div>
              </div>
            </div>
          </Card>
        </div>
      )}

      {/* Admin Actions */}
      <Card variant="default" padding="default">
        <CardHeader className="p-0 pb-4">
          <CardTitle className="text-lg">Admin Actions</CardTitle>
        </CardHeader>
        <div className="flex gap-3">
          <Button variant="success">
            <CheckCircle className="h-4 w-4 mr-2" />
            Force Assign Caregiver
          </Button>
          <Button variant="outline">
            <RefreshCcw className="h-4 w-4 mr-2" />
            Broadcast to All Caregivers
          </Button>
          <Button variant="emergency">
            <XCircle className="h-4 w-4 mr-2" />
            Force Close Alert
          </Button>
          <Button variant="outline">
            <FileText className="h-4 w-4 mr-2" />
            Generate Report
          </Button>
        </div>
      </Card>
    </div>
  );
};

export default AdminSOSCenter;

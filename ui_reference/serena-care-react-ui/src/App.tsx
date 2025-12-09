import { Toaster } from "@/components/ui/toaster";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Routes, Route } from "react-router-dom";

// Pages
import Index from "./pages/Index";
import NotFound from "./pages/NotFound";

// Client App Pages
import ClientHome from "./pages/client/ClientHome";
import ClientBooking from "./pages/client/ClientBooking";
import ClientSOS from "./pages/client/ClientSOS";
import ClientActivity from "./pages/client/ClientActivity";
import ClientProfile from "./pages/client/ClientProfile";

// Caregiver App Pages
import CaregiverHome from "./pages/caregiver/CaregiverHome";
import CaregiverJobs from "./pages/caregiver/CaregiverJobs";
import CaregiverSOSAlerts from "./pages/caregiver/CaregiverSOSAlerts";
import CaregiverChat from "./pages/caregiver/CaregiverChat";
import CaregiverProfile from "./pages/caregiver/CaregiverProfile";

// Admin Panel Pages
import AdminLayout from "./pages/admin/AdminLayout";
import AdminDashboard from "./pages/admin/AdminDashboard";
import AdminUsers from "./pages/admin/AdminUsers";
import AdminCaregivers from "./pages/admin/AdminCaregivers";
import AdminBookings from "./pages/admin/AdminBookings";
import AdminSOSCenter from "./pages/admin/AdminSOSCenter";

const queryClient = new QueryClient();

const App = () => (
  <QueryClientProvider client={queryClient}>
    <TooltipProvider>
      <Toaster />
      <Sonner />
      <BrowserRouter>
        <Routes>
          {/* Landing Page */}
          <Route path="/" element={<Index />} />

          {/* Client App Routes */}
          <Route path="/client" element={<ClientHome />} />
          <Route path="/client/book" element={<ClientBooking />} />
          <Route path="/client/sos" element={<ClientSOS />} />
          <Route path="/client/activity" element={<ClientActivity />} />
          <Route path="/client/profile" element={<ClientProfile />} />

          {/* Caregiver App Routes */}
          <Route path="/caregiver" element={<CaregiverHome />} />
          <Route path="/caregiver/jobs" element={<CaregiverJobs />} />
          <Route path="/caregiver/sos-alerts" element={<CaregiverSOSAlerts />} />
          <Route path="/caregiver/chat" element={<CaregiverChat />} />
          <Route path="/caregiver/profile" element={<CaregiverProfile />} />

          {/* Admin Panel Routes */}
          <Route path="/admin" element={<AdminLayout />}>
            <Route index element={<AdminDashboard />} />
            <Route path="users" element={<AdminUsers />} />
            <Route path="caregivers" element={<AdminCaregivers />} />
            <Route path="bookings" element={<AdminBookings />} />
            <Route path="sos" element={<AdminSOSCenter />} />
          </Route>

          {/* 404 */}
          <Route path="*" element={<NotFound />} />
        </Routes>
      </BrowserRouter>
    </TooltipProvider>
  </QueryClientProvider>
);

export default App;
